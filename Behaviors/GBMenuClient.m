/* GBMenuClient.m - this app's side of the Menu.app global menu bar
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBMenuClient.h"

#import <GNUstepGUI/GSDisplayServer.h>
#import <GNUstepGUI/GSTheme.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortNameServer.h>
#import "GBMenuRelaunchManager.h"

/* The original -[GSTheme setMenu:forWindow:], reachable under this name once
 * GSTheme+GBMenu.m has exchanged the two implementations. */
@interface GSTheme (GBMenuOriginal)
- (void)gb_setMenu:(NSMenu *)m forWindow:(NSWindow *)w;
@end

static BOOL gForceExternalMenuByEnv = NO;
static BOOL gPendingMenuUpdate = NO;
static NSWindow *gPendingMenuWindow = nil;
static BOOL gPendingApplicationMenuPush = NO;
/* Depth of _serializeMenu: calls in progress; see there. */
static NSUInteger gSerializeDepth = 0;

static BOOL GBEnvironmentContainsAppMenuToken(void)
{
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  for (NSString *value in [env allValues])
    {
      if ([value rangeOfString:@"appmenu" options:NSCaseInsensitiveSearch].location != NSNotFound)
        {
          return YES;
        }
    }
  return NO;
}

@implementation GBMenuClient

/* Start as soon as this bundle is loaded rather than on first use: the menu
 * change notifications observed in -init must be in place before the app
 * sets its main menu, and a windowless app is only ever announced to
 * Menu.app by the periodic verification started here.  +load itself runs
 * before the bundle has finished loading, so wait for NSBundle to say so. */
+ (void)load
{
  @autoreleasepool
    {
      __block id observer = nil;
      observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSBundleDidLoadNotification
                    object:nil
                     queue:nil
                usingBlock:^(NSNotification *note) {
                  if ([note object] != [NSBundle bundleForClass:[GBMenuClient class]])
                    return;
                  [[NSNotificationCenter defaultCenter] removeObserver:observer];
                  observer = nil;
                  (void)[GBMenuClient sharedClient];
                }];
    }
}

+ (GBMenuClient *)sharedClient
{
  static GBMenuClient *client = nil;
  if (client == nil)
    {
      client = [[GBMenuClient alloc] init];
    }
  return client;
}

- (id)init
{
  if ((self = [super init]) != nil)
    {
      gForceExternalMenuByEnv = GBEnvironmentContainsAppMenuToken();
      if (gForceExternalMenuByEnv)
        {
          NSDebugLog(@"GBMenuClient: appmenu token detected in environment, forcing external menu mode");
        }

      menuByWindowId = [[NSMutableDictionary alloc] init];
      menuServerAvailable = NO;
      menuServerConnected = NO;

      // Snapshot the current Menu process launch details so restarts can match.
      [[GBMenuRelaunchManager sharedManager] captureMenuProcessSnapshotIfAvailable];

      // Register as a GNUstep menu client so Menu.app can call back for actions
      [self _ensureMenuClientRegistered];

      // Keep the MenuClient registration alive across name-server restarts
      // (a gdnc restart wipes the names registry while the connection stays
      // "valid", so without this the app's menu silently disappears).
      [self performSelector: @selector(scheduleMenuClientVerification)
                 withObject: nil
                 afterDelay: 5.0];

      // Try to connect to Menu.app's GNUstep menu server (may not be running yet)
      [self _ensureMenuServerConnection];

      // Observe menu changes so Menu.app can stay in sync
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(macintoshMenuDidChange:)
               name:@"NSMacintoshMenuDidChangeNotification"
             object:nil];

      // Observe window activation so Menu.app gets menus for newly active windows
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidBecomeKey:)
               name:@"NSWindowDidBecomeKeyNotification"
             object:nil];

      // Observe app activation so a windowless app re-pushes its
      // application-level menu when it becomes the active application
      // (e.g. via Alt-Tab or the app launcher).
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationDidBecomeActive:)
               name:NSApplicationDidBecomeActiveNotification
             object:nil];

      // On termination, unregister the application-level menu.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationWillTerminate:)
               name:NSApplicationWillTerminateNotification
             object:nil];

      // After any menu selection finishes, push updated enabled/state values
      // to Menu.app so items like Copy/Paste reflect the new app state without
      // requiring the user to open a submenu first.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidEndTracking:)
               name:NSMenuDidEndTrackingNotification
             object:nil];

      // After ANY action is sent through a menu item (including keyboard
      // shortcuts matched to menu items), push updated enabled/state values
      // to Menu.app.  This is more efficient than a timer - we only push
      // when something might have changed.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidSendAction:)
               name:NSMenuDidSendActionNotification
             object:nil];

      NSDebugLog(@"GBMenuClient: GNUstep menu IPC initialized (Menu.app %@)",
             menuServerAvailable ? @"available" : @"unavailable");
    }
  return self;
}

/* The in-window menu GSTheme installs by default; used whenever Menu.app
   cannot take the menu, exactly where the theme used to call super. */
- (void)_setStandardMenu:(NSMenu *)m forWindow:(NSWindow *)w
{
  [[GSTheme theme] gb_setMenu: m forWindow: w];
}

- (BOOL)hidesInAppMenuBarForMenu:(NSMenu *)menu
{
  return (menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu);
}

- (NSString *)_menuClientName
{
  if (menuClientName == nil)
    {
      pid_t pid = [[NSProcessInfo processInfo] processIdentifier];
      menuClientName = [[NSString alloc] initWithFormat:@"org.gnustep.Gershwin.MenuClient.%d", pid];
    }
  return menuClientName;
}

- (BOOL)_ensureMenuClientRegistered
{
  if (menuClientConnection != nil)
    {
      /* The connection object is alive, but a name-server restart (gdnc) can
         wipe the whole names registry while leaving the connection "valid" -
         then Menu.app can no longer resolve our MenuClient.<pid> and shows no
         app menu.  Verify the name still resolves; if it does not, drop the
         stale connection so we register fresh below. */
      if ([self _menuClientNameRegistered])
        {
          return YES;
        }
      NSDebugLog(@"GBMenuClient: Menu client registration lost - re-registering");
      [self _teardownMenuClientConnection];
    }

  menuClientConnection = [[NSConnection alloc] init];
  [menuClientConnection setRootObject:self];
  menuClientReceivePort = [menuClientConnection receivePort];
  
  // Don't manually add the port to the runloop - [registerName:] handles this.
  // Manual addPort: creates redundant socket fd polling on every event loop
  // iteration, wasting CPU.

  NSString *clientName = [self _menuClientName];
  BOOL registered = [menuClientConnection registerName:clientName];
  if (!registered)
    {
      NSDebugLog(@"GBMenuClient: Failed to register GNUstep menu client name: %@", clientName);
      if (menuClientReceivePort != nil)
        {
          menuClientReceivePort = nil;
        }
      menuClientConnection = nil;
      return NO;
    }

  // NSDebugLog(@"GBMenuClient: Registered GNUstep menu client as %@ with receive port %@", clientName, [menuClientConnection receivePort]);
  // NSDebugLog(@"GBMenuClient: Registered GNUstep menu client as %@ with receive port added to run loop", clientName);
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:menuClientConnection];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_menuClientConnectionDidDie:)
                                               name:NSConnectionDidDieNotification
                                             object:menuClientConnection];
  return YES;
}

/* Does our MenuClient name still resolve on the DO name server? */
- (BOOL)_menuClientNameRegistered
{
  @try {
    NSConnection *found = [NSConnection connectionWithRegisteredName: [self _menuClientName]
                                                                host: nil];
    if (found)
      {
        [found invalidate];
        return YES;
      }
  } @catch (NSException *e) {
    /* Name server may be restarting; treat as not registered. */
  }
  return NO;
}

/* Drop the client connection state so the next _ensureMenuClientRegistered
   creates and registers a fresh connection. */
- (void)_teardownMenuClientConnection
{
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                 name:NSConnectionDidDieNotification
                                               object:menuClientConnection];
  if (menuClientReceivePort != nil)
    {
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSDefaultRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSModalPanelRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSEventTrackingRunLoopMode];
      [[NSRunLoop currentRunLoop] removePort:menuClientReceivePort
                                     forMode:NSRunLoopCommonModes];
      menuClientReceivePort = nil;
    }
  [menuClientConnection invalidate];
  menuClientConnection = nil;
}

/* Periodic check that our MenuClient.<pid> registration still exists.  A
   name-server restart (gdnc) wipes the names registry but the NSConnection
   stays "valid", so _ensureMenuClientRegistered would normally return early.
   The self-resolve check catches the loss and re-registers. */
- (void)scheduleMenuClientVerification
{
  [self performSelector: @selector(verifyMenuClientRegistration)
             withObject: nil
             afterDelay: 30.0
                inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                  NSModalPanelRunLoopMode, nil]];
}

- (void)verifyMenuClientRegistration
{
  [self _ensureMenuClientRegistered];
  /* A windowless app (no key window ever) has no setMenu:forWindow: call to
     trigger a server connection.  Reconnect here so the app menu reaches
     Menu.app even when Menu.app started after this app - the app-level push
     is Menu.app's only way to learn about such apps. */
  [self _ensureMenuServerConnection];
  [self _pushApplicationMenu];
  [self scheduleMenuClientVerification];
}

- (BOOL)_ensureMenuServerConnection
{
  if (menuServerConnection != nil && ![menuServerConnection isValid])
    {
      menuServerConnection = nil;
      menuServerProxy = nil;
      menuServerConnected = NO;
    }

  if (menuServerProxy != nil)
    {
      return menuServerAvailable;
    }

  NSConnection *connection = [NSConnection connectionWithRegisteredName:@"org.gnustep.Gershwin.MenuServer"
                                                                   host:nil];
  if (connection == nil)
    {
      menuServerConnected = NO;
      return NO;
    }

  menuServerConnection = connection;

  // The synchronous DO calls we make on this connection
  // (updateMenuForWindow:menuData:clientName:) run on the main thread.  Without
  // a request timeout a wedged or busy Menu.app would block our main thread
  // forever and freeze the whole UI (Menu.app sets its own 0.3s timeout on the
  // reverse calls).  Bound the wait so a dead peer can never hang us.
  [menuServerConnection setRequestTimeout:1.0];

  id proxy = [menuServerConnection rootProxy];
  if (proxy != nil)
    {
      [proxy setProtocolForProxy:@protocol(GSGNUstepMenuServer)];
      menuServerProxy = proxy;
      menuServerConnected = YES;
      if (!menuServerAvailable)
        menuServerAvailable = YES;
      [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:menuServerConnection];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(_menuServerConnectionDidDie:)
                                                   name:NSConnectionDidDieNotification
                                                 object:menuServerConnection];
      /* On a fresh connection push our application-level menu immediately, so
         a windowless app appears in the menu bar as soon as Menu.app (re)starts.
         _pushApplicationMenu re-enters _ensureMenuServerConnection, which
         returns YES immediately because menuServerProxy is already set. */
      [self _pushApplicationMenu];
      // NSDebugLog(@"GBMenuClient: Connected to GNUstep menu server");
      return YES;
    }

  menuServerConnection = nil;
  menuServerConnected = NO;
  return NO;
}

- (NSNumber *)_windowIdentifierForWindow:(NSWindow *)window
{
  GSDisplayServer *server = GSServerForWindow(window);
  if (server == nil)
    {
      return nil;
    }

  int internalNumber = [window windowNumber];
  uint32_t deviceId = (uint32_t)(uintptr_t)[server windowDevice:internalNumber];

  return [NSNumber numberWithUnsignedInt:deviceId];
}

- (NSDictionary *)_serializeMenuItem:(NSMenuItem *)item
{
  if (item == nil)
    {
      return nil;
    }

  if ([item isSeparatorItem])
    {
      return [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                         forKey:@"isSeparator"];
    }

  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  [dict setObject:([item title] ?: @"") forKey:@"title"];
  [dict setObject:[NSNumber numberWithBool:[item isEnabled]] forKey:@"enabled"];
  [dict setObject:[NSNumber numberWithInteger:[item state]] forKey:@"state"];
  [dict setObject:([item keyEquivalent] ?: @"") forKey:@"keyEquivalent"];
  [dict setObject:[NSNumber numberWithUnsignedInteger:[item keyEquivalentModifierMask]]
           forKey:@"keyEquivalentModifierMask"];

  if ([item hasSubmenu])
    {
      NSDictionary *submenu = [self _serializeMenu:[item submenu]];
      if (submenu != nil)
        {
          [dict setObject:submenu forKey:@"submenu"];
        }
    }

  return dict;
}

- (NSDictionary *)_serializeMenu:(NSMenu *)menu
{
  NSDictionary *result = nil;

  if (menu == nil)
    {
      return nil;
    }

  /* Validating the items changes their enabled state, and every change
     reaches macintoshMenuDidChange:, which would start another full
     serialization and a synchronous push to Menu.app from inside this one -
     one Menu.app round trip per changed item.  The depth lets that handler
     ignore the changes we cause here, and lets the submenus serialized
     through _serializeMenuItem: skip validating a tree the outermost call
     has already validated. */
  gSerializeDepth++;
  @try
    {
      if (gSerializeDepth == 1)
        {
          [self _recursiveMenuUpdate:menu];
        }

      NSMutableArray *items = [NSMutableArray array];
      NSArray *itemArray = [menu itemArray];
      NSUInteger count = [itemArray count];

      for (NSUInteger i = 0; i < count; i++)
        {
          NSMenuItem *item = [itemArray objectAtIndex:i];
          NSDictionary *serialized = [self _serializeMenuItem:item];
          if (serialized != nil)
            {
              [items addObject:serialized];
            }
        }

      result = [NSDictionary dictionaryWithObjectsAndKeys:
                          ([menu title] ?: @""), @"title",
                          items, @"items",
                          nil];
    }
  @finally
    {
      gSerializeDepth--;
    }

  return result;
}

// Helper: serialize menu with index-paths so remote clients can refer to specific
// menu items deterministically.
- (NSDictionary *)_serializeMenuWithIndexPaths:(NSMenu *)menu
{
  if (menu == nil) return nil;
  NSMutableArray *items = [NSMutableArray array];
  NSArray *itemArray = [menu itemArray];
  for (NSUInteger i = 0; i < [itemArray count]; i++) {
    NSMenuItem *item = itemArray[i];
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"title"] = ([item title] ?: @"");
    d[@"enabled"] = @([item isEnabled]);
    d[@"state"] = @([item state]);
    d[@"isSeparator"] = @([item isSeparatorItem]);
    d[@"indexPath"] = @[@(i)];
    if ([item hasSubmenu]) {
      d[@"submenu"] = [self _serializeMenuWithIndexPaths:[item submenu]];
    }
    [items addObject:d];
  }
  return @{ @"title": ([menu title] ?: @""), @"items": items };
}

// Helper: walk a serialized menu item tree and generate a unique ID for each
// item. Format: menuitem:<windowId>:<idx0>.<idx1>...
- (NSString *)_menuItemIDForWindow:(NSNumber *)windowId indexPath:(NSArray *)indexPath
{
  NSMutableArray *parts = [NSMutableArray array];
  for (NSNumber *n in indexPath) [parts addObject:[n stringValue]];
  NSString *path = [parts componentsJoinedByString:@"."];
  return [NSString stringWithFormat:@"menuitem:%@:%@", windowId ?: @0, path ?: @"0"];
}

- (NSMenuItem *)_menuItemForIndexPath:(NSArray *)indexPath inMenu:(NSMenu *)menu
{
  if (menu == nil || indexPath == nil || [indexPath count] == 0)
    {
      return nil;
    }

  NSMenu *currentMenu = menu;
  NSMenuItem *currentItem = nil;

  for (NSUInteger i = 0; i < [indexPath count]; i++)
    {
      NSNumber *indexNumber = [indexPath objectAtIndex:i];
      NSInteger index = [indexNumber integerValue];
      if (index < 0 || index >= [currentMenu numberOfItems])
        {
          return nil;
        }

      currentItem = [currentMenu itemAtIndex:index];
      if (i < [indexPath count] - 1)
        {
          if (![currentItem hasSubmenu])
            {
              return nil;
            }
          currentMenu = [currentItem submenu];
        }
    }

  return currentItem;
}

- (void)_menuClientConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"GBMenuClient: Menu client connection died");
  [self _teardownMenuClientConnection];
  /* Re-register so Menu.app keeps seeing this app's menu after a name-server
     restart. */
  [self _ensureMenuClientRegistered];
}

- (void)_menuServerConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"GBMenuClient: Menu server connection died");
  menuServerConnection = nil;
  menuServerProxy = nil;
  menuServerConnected = NO;
  /* Reconnect immediately and re-push the application-level menu so a
     windowless app's menu survives a Menu.app restart. */
  [self _ensureMenuServerConnection];
  [self _pushApplicationMenu];
  // Automatic Menu.app restart disabled.
  // [[GBMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
}

/* Opening a window can change many menu items at once; a synchronous push
   of the whole application menu for each of them stalled the app for
   seconds, so the pushes are coalesced like gb_sendPendingMenu. */
- (void) _schedulePushApplicationMenu
{
  if (gPendingApplicationMenuPush)
    {
      return;
    }
  gPendingApplicationMenuPush = YES;
  [self performSelector: @selector(gb_sendPendingApplicationMenu)
             withObject: nil
             afterDelay: 0.1];
}

- (void) gb_sendPendingApplicationMenu
{
  gPendingApplicationMenuPush = NO;
  [self _pushApplicationMenu];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];

  if (gSerializeDepth > 0)
    {
      /* Caused by the validation in _serializeMenu:, whose result already
         carries the new state. */
      return;
    }

  if ([NSApp mainMenu] == menu)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          NSDebugLog(@"GBMenuClient: Syncing GNUstep menu for key window: %@", keyWindow);
          [self setMenu: menu forWindow: keyWindow];
        }
      else
        {
          NSDebugLog(@"GBMenuClient: No key window available for menu change notification");
        }
      /* Always keep the application-level menu in sync too.  This is what the
         menu bar shows when the app is frontmost but has no window (windowless
         app, or the last window closed). */
      [self _schedulePushApplicationMenu];
    }
}

- (void) applicationDidBecomeActive: (NSNotification*)notification
{
  (void)notification;
  /* A windowless app can become the active application (e.g. via Alt-Tab or
     the app launcher) without any window becoming key.  Re-push the app menu
     so Menu.app is guaranteed to show it. */
  [self _pushApplicationMenu];
}

- (void) applicationWillTerminate: (NSNotification*)notification
{
  (void)notification;
  if (!menuServerProxy)
    {
      return;
    }
  @try
    {
      [(id<GSGNUstepMenuServer>)menuServerProxy unregisterApplication:[self _menuClientName]];
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"GBMenuClient: Exception unregistering application menu: %@", exception);
    }
}

- (void) windowDidBecomeKey: (NSNotification*)notification
{
  NSWindow *window = [notification object];
  
  // When a window becomes key, send its menu to Menu.app
  // This ensures menus are available when the Menu component scans after window activation
  NSMenu *mainMenu = [NSApp mainMenu];

  if (mainMenu != nil && [mainMenu numberOfItems] > 0)
    {
      NSDebugLog(@"GBMenuClient: Window became key, syncing GNUstep menu: %@", window);
      [self setMenu: mainMenu forWindow: window];
    }
  else
    {
      NSDebugLog(@"GBMenuClient: Window became key but no main menu available: %@", window);
    }
}

- (void) sendMenu:(NSWindow*)w {

  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  NSDebugLog(@"GBMenuClient: sendMenu");
  NSMenu *m = [menuByWindowId objectForKey:windowId];

  @try
    {
      // NSDebugLog(@"GBMenuClient: Calling updateMenuForWindow on Menu.app server proxy");
      NSDictionary *menuData = [self _serializeMenu:m];

      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForWindow:windowId
							   menuData:menuData
							 clientName:[self _menuClientName]];
      NSDebugLog(@"GBMenuClient: Successfully sent menu update to Menu.app");
      NSDebugLog(@"GBMenuClient: Updated GNUstep menu for window %@", windowId);
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"GBMenuClient: Exception sending GNUstep menu: %@, falling back to standard menu", exception);
      if (!gForceExternalMenuByEnv)
        {
          [self _setStandardMenu: m forWindow: w];
        }
    }
  

}

/* Push this app's application-level menu (its main menu) to Menu.app.  This
   is the menu the global bar shows when the app is the frontmost application
   but has no window (windowless app, or the last window closed).  This
   serializes the whole menu and waits for Menu.app, so frequent callers go
   through _schedulePushApplicationMenu. */
- (void) _pushApplicationMenu
{
  NSMenu *mainMenu = [NSApp mainMenu];
  if (mainMenu == nil || [mainMenu numberOfItems] == 0)
    {
      return;
    }

  if (![self _ensureMenuClientRegistered])
    {
      return;
    }
  if (![self _ensureMenuServerConnection])
    {
      return;
    }

  @try
    {
      NSDictionary *menuData = [self _serializeMenu:mainMenu];
      if (!menuData)
        {
          return;
        }
      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForApplication:menuData
                                                              clientName:[self _menuClientName]];
      NSDebugLog(@"GBMenuClient: Pushed application-level menu to Menu.app");
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"GBMenuClient: Exception pushing application-level menu: %@", exception);
    }
}

/* Menu.app asks the client to re-push its application-level menu (startup
   recovery, or after the app's last window closed). */
- (oneway void)requestApplicationMenuUpdate
{
  NSDebugLog(@"GBMenuClient: requestApplicationMenuUpdate called");

  if (![NSThread isMainThread])
    {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self requestApplicationMenuUpdate];
      });
      return;
    }

  [self _pushApplicationMenu];
}

#pragma mark - Menu state push

// Push only the enabled/state values for the current key window's menu to
// Menu.app without a full menu rebuild.  This is called after menu tracking
// ends so that PostScript/Paste/Select All etc. immediately update the menu
// bar when the user next looks at it.
- (void)_pushMenuEnabledStates
{
  if (!menuServerProxy) return;

  NSWindow *keyWindow = [NSApp keyWindow];
  if (!keyWindow) return;

  NSNumber *windowId = [self _windowIdentifierForWindow:keyWindow];
  if (!windowId) return;

  NSMenu *menu = [menuByWindowId objectForKey:windowId];
  if (!menu) return;

  @try
    {
      // Recursively validate ALL items (visible and hidden) before we push
      // states to Menu.app.  Without this, submenu items retain stale
      // enabled/state values.
      [self _recursiveMenuUpdate:menu];

      // Serialize with index paths - includes fresh enabled/state after [menu update]
      NSDictionary *menuData = [self _serializeMenuWithIndexPaths:menu];
      if (menuData)
        {
          [(id<GSGNUstepMenuServer>)menuServerProxy
            updateMenuEnabledStatesForWindow:windowId
                                    menuData:menuData
                                  clientName:[self _menuClientName]];
          NSDebugLog(@"GBMenuClient: Pushed enabled states for window %@", windowId);
        }
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"GBMenuClient: Exception pushing enabled states: %@", exception);
    }

  /* Also refresh the application-level menu's enabled/state values so a
     windowless frontmost app sees fresh states in the menu bar. */
  NSMenu *mainMenu = [NSApp mainMenu];
  if (mainMenu && [mainMenu numberOfItems] > 0)
    {
      @try
        {
          [self _recursiveMenuUpdate:mainMenu];
          NSDictionary *appMenuData = [self _serializeMenuWithIndexPaths:mainMenu];
          if (appMenuData)
            {
              [(id<GSGNUstepMenuServer>)menuServerProxy
                updateApplicationMenuEnabledStates:appMenuData
                                        clientName:[self _menuClientName]];
            }
        }
      @catch (NSException *exception)
        {
          NSDebugLog(@"GBMenuClient: Exception pushing application enabled states: %@", exception);
        }
    }
}

// Recursively call [menu update] on the given menu and ALL its submenus,
// regardless of visibility.  GNUstep's built-in [NSMenu update] only calls
// _autoenableItem: on items in visible menus (via _updateSubmenu); hidden
// submenus keep stale enabled states.  This helper ensures every item in the
// tree gets fresh validation before we push states to Menu.app.
- (void)_recursiveMenuUpdate:(NSMenu *)menu
{
  if (!menu) return;
  [menu update];
  for (NSMenuItem *item in [menu itemArray])
    {
      if ([item hasSubmenu])
        {
          [self _recursiveMenuUpdate:[item submenu]];
        }
    }
}

// NSMenuDidSendActionNotification - fired after ANY action is sent through a
// menu item, including keyboard shortcuts that match menu items.  We push
// updated enabled/state to Menu.app so the menu bar is always current.
// This is more efficient than a polling timer - we only push when something
// might have changed.
- (void)menuDidSendAction:(NSNotification *)note
{
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _pushMenuEnabledStates];
  });
}

// NSMenuDidEndTrackingNotification - fired after any menu tracking session
// finishes.  Extra safety net for cases where the action is sent outside
// the menu item path.
- (void)menuDidEndTracking:(NSNotification *)note
{
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _pushMenuEnabledStates];
  });
}

- (void) setMenu:(NSMenu*)m forWindow:(NSWindow*)w
{
  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  if (windowId == nil)
    {
      NSDebugLog(@"GBMenuClient: Could not resolve window identifier, using standard menu for window: %@", w);
      NSDebugLog(@"GBMenuClient: Could not resolve window identifier, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [self _setStandardMenu: m forWindow: w];
        }
      return;
    }

  if (m == nil || [m numberOfItems] == 0)
    {
      NSDebugLog(@"GBMenuClient: Menu is nil or empty (items=%ld)", (long)[m numberOfItems]);
      BOOL hadMenu = ([menuByWindowId objectForKey:windowId] != nil);
      [menuByWindowId removeObjectForKey:windowId];

      if (hadMenu && [self _ensureMenuServerConnection])
        {
          @try
            {
              NSDebugLog(@"GBMenuClient: Unregistering window %@ from Menu.app", windowId);
              [(id<GSGNUstepMenuServer>)menuServerProxy unregisterWindow:windowId
                                                                clientName:[self _menuClientName]];
            }
          @catch (NSException *exception)
            {
              NSDebugLog(@"GBMenuClient: Exception unregistering window %@: %@", windowId, exception);
              NSDebugLog(@"GBMenuClient: Exception unregistering window %@: %@", windowId, exception);
            }
        }

      NSDebugLog(@"GBMenuClient: Menu is nil or empty, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [self _setStandardMenu: m forWindow: w];
        }
      return;
    }

  // NSDebugLog(@"GBMenuClient: Storing menu in cache for windowId=%@, menu has %ld items", windowId, (long)[m numberOfItems]);
  // TOM: i believe this is redundant
  // [m update];

  [menuByWindowId setObject:m forKey:windowId];

  if (![self _ensureMenuClientRegistered])
    {
      NSDebugLog(@"GBMenuClient: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      NSDebugLog(@"GBMenuClient: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [self _setStandardMenu: m forWindow: w];
        }
      return;
    }

  if (![self _ensureMenuServerConnection])
    {
      NSDebugLog(@"GBMenuClient: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      NSDebugLog(@"GBMenuClient: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      // [[GBMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
      return;
    }

  // Rate-limited menu updating (coalesced to avoid messaging freed objects)
  gPendingMenuWindow = w;
  if (!gPendingMenuUpdate)
    {
      gPendingMenuUpdate = YES;
      [self performSelector: @selector(gb_sendPendingMenu)
                 withObject: nil
                 afterDelay: 0.1];
    }
}

- (void) gb_sendPendingMenu
{
  gPendingMenuUpdate = NO;
  NSWindow *win = gPendingMenuWindow;
  gPendingMenuWindow = nil;
  if (win)
    {
      [self sendMenu: win];
    }
}

- (void)_performMenuActionFromIPC:(NSDictionary *)info
{
  NSNumber *windowId = [info objectForKey:@"windowId"];
  NSArray *indexPath = [info objectForKey:@"indexPath"];

  /* Each early return below drops a menu action sent by Menu.app; log them,
     since a dropped action otherwise leaves no trace at all. */
  if (windowId == nil || indexPath == nil)
    {
      NSLog(@"GBMenuClient: dropping menu action: window %@, index path %@", windowId, indexPath);
      return;
    }

  NSMenu *menu = [menuByWindowId objectForKey:windowId];
  if (menu == nil)
    {
      if ([menuByWindowId count] == 1)
        {
          menu = [[menuByWindowId allValues] firstObject];
        }
      else if ([menuByWindowId count] > 0)
        {
          menu = [[menuByWindowId allValues] firstObject];
        }

      if (menu == nil)
        {
          menu = [NSApp mainMenu];
        }

      if (menu == nil)
        {
          NSLog(@"GBMenuClient: dropping menu action %@: no menu for window %@", indexPath, windowId);
          return;
        }
    }

  NSMenuItem *menuItem = [self _menuItemForIndexPath:indexPath inMenu:menu];
  if (menuItem == nil)
    {
      NSLog(@"GBMenuClient: dropping menu action: no item at %@ in the menu of window %@", indexPath, windowId);
      return;
    }

  /* The enabled flag is only as fresh as the last validation, which AppKit
     runs after X events.  An action that arrived over DO (e.g. Select All from
     Menu.app) changes the state without such an event, so a Copy chosen right
     after it would be dropped as disabled. */
  [[menuItem menu] update];
  if (![menuItem isEnabled])
    {
      NSLog(@"GBMenuClient: dropping menu action '%@': item is disabled", [menuItem title]);
      return;
    }

  SEL action = [menuItem action];
  id target = [menuItem target];

  if (action == NULL)
    {
      NSLog(@"GBMenuClient: dropping menu action '%@': item has no action", [menuItem title]);
      return;
    }

  [NSApp sendAction:action to:target from:menuItem];
}

- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath forWindow:(NSNumber *)windowId
{
  NSDebugLog(@"GBMenuClient: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  NSDebugLog(@"GBMenuClient: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  
  NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                           indexPath ?: [NSArray array], @"indexPath",
                           windowId ?: [NSNumber numberWithUnsignedInt:0], @"windowId",
                           nil];

  if (![NSThread isMainThread])
    {
      /* Logged because the action then depends on the libdispatch main
         queue being drained by the run loop; if it never runs, this line is
         the only trace. */
      NSLog(@"GBMenuClient: menu action %@ arrived off the main thread, handing it to the main queue", indexPath);
      dispatch_async(dispatch_get_main_queue(), ^{
        [self _performMenuActionFromIPC:payload];
      });
      return;
    }

  NSDebugLog(@"GBMenuClient: On main thread, calling _performMenuActionFromIPC directly");
  [self _performMenuActionFromIPC:payload];
}

// Recursively collect @[title, enabled, state] triples from a menu tree.
// Returns a flat NSArray - no nested dictionaries - so it copies over DO
// in a single batch regardless of bycopy support.
- (NSArray *)_collectFlatStates:(NSMenu *)menu
{
  NSMutableArray *result = [NSMutableArray array];
  for (NSMenuItem *item in [menu itemArray]) {
    if ([item isSeparatorItem]) continue;
    NSString *title = [item title];
    if (!title || [title length] == 0) continue;
    [result addObject:@[ title, @([item isEnabled]), @([item state]) ]];
    if ([item hasSubmenu]) {
      [result addObjectsFromArray:[self _collectFlatStates:[item submenu]]];
    }
  }
  return result;
}

- (bycopy id)validateMenuStateForWindow:(NSNumber *)windowId
{
  NSDebugLog(@"GBMenuClient: validateMenuStateForWindow called - windowId: %@", windowId);

  if (![NSThread isMainThread])
    {
      __block id result = nil;
      dispatch_sync(dispatch_get_main_queue(), ^{
        result = [self validateMenuStateForWindow:windowId];
      });
      return result;
    }

  // Find the menu for this window
  NSMenu *menu = nil;
  if (windowId)
    {
      menu = [menuByWindowId objectForKey:windowId];
    }

  // Fallback: use key window's menu
  if (!menu)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow)
        {
          NSNumber *keyWinId = [self _windowIdentifierForWindow:keyWindow];
          if (keyWinId)
            {
              menu = [menuByWindowId objectForKey:keyWinId];
            }
        }
    }

  // Last resort: first cached menu
  if (!menu && [menuByWindowId count] > 0)
    {
      menu = [[menuByWindowId allValues] firstObject];
    }

  // Final fallback: the application's main menu (windowless app, or the
  // menu was never associated with a window).
  if (!menu)
    {
      menu = [NSApp mainMenu];
    }

  if (!menu)
    {
      NSDebugLog(@"GBMenuClient: validateMenuStateForWindow: no menu found for window %@", windowId);
      return nil;
    }

  // Recursively validate ALL items before collecting states
  [self _recursiveMenuUpdate:menu];

  // Return a flat array of @[title, enabled, state] triples.
  // No nested dictionaries - copies over DO in one batch instantly.
  NSArray *flat = [self _collectFlatStates:menu];
  NSDebugLog(@"GBMenuClient: validateMenuStateForWindow: returning %lu flat items for window %@",
         (unsigned long)[flat count], windowId);
  return flat;
}

- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId
{
  NSDebugLog(@"GBMenuClient: requestMenuUpdateForWindow called - windowId: %@", windowId);
  NSDebugLog(@"GBMenuClient: requestMenuUpdateForWindow called - windowId: %@", windowId);

  if (![NSThread isMainThread])
    {
      dispatch_async(dispatch_get_main_queue(), ^{
        [self requestMenuUpdateForWindow:windowId];
      });
      return;
    }

  // Find the window and push its menu to Menu.app
  NSWindow *targetWindow = nil;
  for (NSWindow *w in [NSApp windows])
    {
      NSNumber *wid = [self _windowIdentifierForWindow:w];
      if (wid && [wid isEqualToNumber:windowId])
        {
          targetWindow = w;
          break;
        }
    }

  if (!targetWindow)
    {
      // Fallback: use key window
      targetWindow = [NSApp keyWindow];
    }

  if (targetWindow)
    {
      NSDebugLog(@"GBMenuClient: requestMenuUpdateForWindow: pushing menu for window %@", windowId);
      [self setMenu:[NSApp mainMenu] forWindow:targetWindow];
    }
  else
    {
      NSDebugLog(@"GBMenuClient: requestMenuUpdateForWindow: no window found for %@, cannot push", windowId);
    }
}

@end
