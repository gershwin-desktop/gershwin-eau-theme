#import "Eau.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortNameServer.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"
#import "EauMenuRelaunchManager.h"
#import "AppearanceMetrics.h"

/* Process-wide GSScaleFactor cache used by the AppearanceMetrics macros;
 * reset by -invalidateScaleFactorCache for live scale-factor changes. */
CGFloat GSWScaleFactorValue = 0;

@interface Eau (NSWindowTitle)
+ (void)EAUswizzleNSWindowSetTitle;
+ (void)EAUswizzleGSStandardOffsets;
@end

/* Private window-decoration methods implemented in Eau+WindowDecoration.m */
@interface Eau (EauWindowDecoration)
- (void)invalidateTitleTextAttributes;
@end

/* Only one Eau instance is the active theme at a time.  GSTheme creates a
 * fresh instance on every +setTheme:, and the old one can outlive the switch
 * (its DO connection keeps it alive), so the flag is tied to the instance
 * that last activated rather than to "an Eau exists". */
static __unsafe_unretained Eau *gActiveEauTheme = nil;

static BOOL gForceExternalMenuByEnv = NO;
static BOOL gPendingMenuUpdate = NO;
static NSWindow *gPendingMenuWindow = nil;
static BOOL gPendingApplicationMenuPush = NO;
/* Depth of _serializeMenu: calls in progress; see there. */
static NSUInteger gSerializeDepth = 0;

static BOOL EauEnvironmentContainsAppMenuToken(void)
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

// Implementation of safe color conversion helper
NSColor *EauSafeCalibratedRGB(NSColor *c)
{
  if (!c) return nil;

  @try {
    if ([c respondsToSelector:@selector(colorUsingColorSpaceName:)]) {
      NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      if (rgb) return rgb;
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: conversion threw: %@, falling back", ex);
  }

  // Try grayscale fallback
  @try {
    if ([c respondsToSelector:@selector(whiteComponent)]) {
      CGFloat w = [c whiteComponent];
      CGFloat a = ([c respondsToSelector:@selector(alphaComponent)] ? [c alphaComponent] : 1.0);
      return [NSColor colorWithCalibratedWhite:w alpha:a];
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: whiteComponent threw: %@, falling back", ex);
  }

  // Final fallback: light control background
  return [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
}

@implementation Eau

/* Reset the cached GSScaleFactor so the next render picks up a live change. */
- (void)invalidateScaleFactorCache
{
  GSWScaleFactorInvalidate();
  [self invalidateTitleTextAttributes];
}

/* Maximum size for the icon shown in front of a menu item (the image column,
 * used for application and preference-pane icons).  Icons are scaled down to
 * fit this box, never up, so a large app bundle icon renders small. */
- (CGFloat) menuItemIconSize
{
  return 18.0;
}

+ (void)load
{
  // Swizzle NSWindow setTitle: to add middle-ellipsis truncation for long titles
  [self EAUswizzleNSWindowSetTitle];

  // Match GNUstep's window frame offsets to the WM's real frame (no 1px
  // border in compositor mode) so window geometry round-trips pixel-exact.
  [self EAUswizzleGSStandardOffsets];

  gForceExternalMenuByEnv = EauEnvironmentContainsAppMenuToken();
  if (gForceExternalMenuByEnv)
    {
      NSDebugLog(@"Eau: appmenu token detected in environment, forcing external menu mode");
    }
  // NSLog(@"Eau: +load called");
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
      NSDebugLog(@"Eau: Menu client registration lost - re-registering");
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
      NSDebugLog(@"Eau: Failed to register GNUstep menu client name: %@", clientName);
      if (menuClientReceivePort != nil)
        {
          menuClientReceivePort = nil;
        }
      menuClientConnection = nil;
      return NO;
    }

  // NSDebugLog(@"Eau: Registered GNUstep menu client as %@ with receive port %@", clientName, [menuClientConnection receivePort]);
  // NSDebugLog(@"Eau: Registered GNUstep menu client as %@ with receive port added to run loop", clientName);
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
      // NSDebugLog(@"Eau: Connected to GNUstep menu server");
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

- (id)initWithBundle:(NSBundle *)bundle
{
  NSDebugLog(@"Eau: >>> initWithBundle ENTRY (before super init)");

  /* Before GSTheme looks at this class' override methods for the first time,
     so that what it replaces is on record. */
  EauRecordOriginalOverriddenMethods();

  if ((self = [super initWithBundle:bundle]) != nil)
    {
      NSDebugLog(@"Eau: >>> initWithBundle after super init, self=%p", self);
      NSDebugLog(@"Eau: Initializing theme with bundle: %@", bundle);

      menuByWindowId = [[NSMutableDictionary alloc] init];
      menuServerAvailable = NO;
      menuServerConnected = NO;
      menuIntegrationRunning = NO;

      /* The menu IPC is deliberately not started here: GSTheme instantiates a
         theme to inspect it (and on every switch) without necessarily making
         it current, and a second registered MenuClient would fight the active
         one.  -activate starts it, -deactivate stops it again. */

      // Ensure alternating row background color is visible in Eau theme
      // Note: System color list may be read-only, so we wrap in try-catch
      NSDebugLog(@"Eau: >>> About to check system color list");
      @try
        {
          NSColorList *systemColors = [NSColorList colorListNamed: @"System"];
          NSDebugLog(@"Eau: >>> System color list: %p, isEditable: %d",
                 systemColors, systemColors ? [systemColors isEditable] : -1);
          if (systemColors != nil && [systemColors isEditable])
            {
              NSDebugLog(@"Eau: >>> Setting alternateRowBackgroundColor");
              // Light gray with a touch of blue
              [systemColors setColor: [NSColor colorWithCalibratedRed: 0.94
                                                                 green: 0.95
                                                                  blue: 0.97
                                                                 alpha: 1.0]
                               forKey: @"alternateRowBackgroundColor"];
              NSDebugLog(@"Eau: >>> alternateRowBackgroundColor set successfully");
            }
          else
            {
              NSDebugLog(@"Eau: >>> Skipping color list modification (nil or not editable)");
            }
        }
      @catch (NSException *exception)
        {
          NSDebugLog(@"Eau: Could not set alternating row color: %@", [exception reason]);
        }
      NSDebugLog(@"Eau: >>> initWithBundle EXIT");
    }
  return self;
}    

#pragma mark - Theme activation

/* Everything Eau does beyond drawing - the swizzles in the category files and
   the Menu.app IPC - is switched on here and off in -deactivate, so another
   theme can take over in a running application. */
- (void) activate
{
  gActiveEauTheme = self;
  EauSetThemeActive(YES);

  /* Before [GSTheme activate], which re-establishes the main menu and asks
     -proposedVisibility:forMenu: whether the application's own menu bar
     belongs on the screen.  The answer is "no" only once Menu.app has been
     reached, so connecting afterwards would leave that bar mapped on top of
     the global one for the rest of the session. */
  [self _startMenuIntegration];

  [super activate];

  /* The application's own menu bar may be on the screen from the theme that
     was in charge until now; -[NSMenu setMain:] leaves a menu that is already
     showing where it is, and what [GSTheme activate] has just re-established
     is not put on the screen again but not taken off it either. */
  [self _hideInApplicationMenuBarIfServedExternally];
}

/* The application's own menu bar has no business being on the screen while
   Menu.app shows the menu; -proposedVisibility:forMenu: says which of the two
   is in charge. */
- (void) _hideInApplicationMenuBarIfServedExternally
{
  NSMenu *mainMenu = [NSApp mainMenu];

  if (mainMenu == nil || [self proposedVisibility: YES forMenu: mainMenu])
    {
      return;
    }
  [mainMenu close];
}

- (void) deactivate
{
  /* Stop the IPC while the flag is still set: unregistering our windows needs
     the menu client name, and Menu.app must drop us before the in-application
     menu bar comes back. */
  [self _stopMenuIntegration];

  if (gActiveEauTheme == self)
    {
      gActiveEauTheme = nil;
      EauSetThemeActive(NO);
    }

  [super deactivate];

  /* GSTheme restores whatever it believed the previous implementations were;
     that belief is wrong whenever this instance was built while another Eau
     instance was already active, so put the real originals back.  What Eau
     put into live windows - the title bar buttons, the resize grip - is taken
     out by EauThemeSwitchWatcher when the incoming theme activates, which is
     the only moment replacements for them can be asked for. */
  EauRestoreOverriddenMethods();

  /* Hand the menu bar back to the application.  While Eau was active its own
     bar was never put on the screen (see -activate), and -[NSMenu setMain:],
     which the incoming theme runs, re-establishes the bar from whatever state
     it finds - so it has to be told that the menu is the main one again now
     that nothing serves it from outside. */
  [[NSApp mainMenu] setMain: YES];
}

/* -[NSColor themeDidActivate:] completes a theme's system colour list with the
   defaults the theme does not define, and raises
   NSColorListNotEditableException when the list came straight out of a
   read-only bundle - which cuts that method short, before it announces
   NSSystemColorsDidChangeNotification, on every single activation.  Hand out a
   copy that can take those additions. */
- (NSColorList *) colors
{
  NSColorList *list = [super colors];
  NSEnumerator *enumerator;
  NSString *key;

  if (list == nil || [list isEditable])
    {
      return list;
    }

  if (editableSystemColors == nil)
    {
      editableSystemColors = [[NSColorList alloc] initWithName: [list name]];
      enumerator = [[list allKeys] objectEnumerator];
      while ((key = [enumerator nextObject]) != nil)
        {
          [editableSystemColors setColor: [list colorWithKey: key]
                                  forKey: key];
        }
    }
  return editableSystemColors;
}

/* Start talking to Menu.app.  Idempotent - a theme may be activated twice
   (GSTheme does that itself when a theme updates its own resources). */
- (void) _startMenuIntegration
{
  if (menuIntegrationRunning)
    {
      return;
    }
  menuIntegrationRunning = YES;

  // Snapshot the current Menu process launch details so restarts can match.
  [[EauMenuRelaunchManager sharedManager] captureMenuProcessSnapshotIfAvailable];

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

  /* An application that is already running when the theme is switched on has
     its menu and key window in place already; nothing will notify us about
     them, so push once now. */
  [self _pushApplicationMenu];
  {
    NSWindow *keyWindow = [NSApp keyWindow];
    NSMenu *mainMenu = [NSApp mainMenu];
    if (keyWindow != nil && mainMenu != nil && [mainMenu numberOfItems] > 0)
      {
        [self setMenu: mainMenu forWindow: keyWindow];
      }
  }

  NSDebugLog(@"Eau: GNUstep menu IPC initialized (Menu.app %@)",
         menuServerAvailable ? @"available" : @"unavailable");
}

/* Hand the menu bar back.  Menu.app keeps an entry per client name, so we have
   to withdraw every window and the application entry explicitly - otherwise
   the global bar would keep showing a menu for an application that has gone
   back to drawing its own. */
- (void) _stopMenuIntegration
{
  if (!menuIntegrationRunning)
    {
      return;
    }
  menuIntegrationRunning = NO;

  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  gPendingMenuUpdate = NO;
  gPendingMenuWindow = nil;
  gPendingApplicationMenuPush = NO;

  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: @"NSMacintoshMenuDidChangeNotification"
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: @"NSWindowDidBecomeKeyNotification"
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSApplicationDidBecomeActiveNotification
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSApplicationWillTerminateNotification
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSMenuDidEndTrackingNotification
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSMenuDidSendActionNotification
                                                object: nil];

  if (menuServerProxy != nil)
    {
      NSString *clientName = [self _menuClientName];
      NSArray *windowIds = [menuByWindowId allKeys];
      NSEnumerator *e = [windowIds objectEnumerator];
      NSNumber *windowId;

      while ((windowId = [e nextObject]) != nil)
        {
          @try
            {
              [(id<GSGNUstepMenuServer>)menuServerProxy unregisterWindow: windowId
                                                              clientName: clientName];
            }
          @catch (NSException *exception)
            {
              NSDebugLog(@"Eau: Exception unregistering window %@ on deactivate: %@",
                         windowId, exception);
            }
        }

      @try
        {
          [(id<GSGNUstepMenuServer>)menuServerProxy unregisterApplication: clientName];
        }
      @catch (NSException *exception)
        {
          NSDebugLog(@"Eau: Exception unregistering application on deactivate: %@", exception);
        }
    }

  [menuByWindowId removeAllObjects];

  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSConnectionDidDieNotification
                                                object: menuServerConnection];
  menuServerConnection = nil;
  menuServerProxy = nil;
  menuServerConnected = NO;
  menuServerAvailable = NO;

  /* The registered name has to go as well, or the Eau instance that a later
     switch back creates cannot claim MenuClient.<pid> and would be invisible
     to Menu.app. */
  [self _teardownMenuClientConnection];

  NSDebugLog(@"Eau: GNUstep menu IPC stopped");
}

- (void) dealloc
{
  [self _stopMenuIntegration];
  [[NSNotificationCenter defaultCenter] removeObserver: self];
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
}

- (void)_menuClientConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"Eau: Menu client connection died");
  [self _teardownMenuClientConnection];
  /* Re-register so Menu.app keeps seeing this app's menu after a name-server
     restart. */
  [self _ensureMenuClientRegistered];
}

- (void)_menuServerConnectionDidDie:(NSNotification *)notification
{
  NSDebugLog(@"Eau: Menu server connection died");
  menuServerConnection = nil;
  menuServerProxy = nil;
  menuServerConnected = NO;
  /* Reconnect immediately and re-push the application-level menu so a
     windowless app's menu survives a Menu.app restart. */
  [self _ensureMenuServerConnection];
  [self _pushApplicationMenu];
  // Automatic Menu.app restart disabled.
  // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
}

/* Opening a window can change many menu items at once; a synchronous push
   of the whole application menu for each of them stalled the app for
   seconds, so the pushes are coalesced like eau_sendPendingMenu. */
- (void) _schedulePushApplicationMenu
{
  if (gPendingApplicationMenuPush)
    {
      return;
    }
  gPendingApplicationMenuPush = YES;
  [self performSelector: @selector(eau_sendPendingApplicationMenu)
             withObject: nil
             afterDelay: 0.1];
}

- (void) eau_sendPendingApplicationMenu
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
          NSDebugLog(@"Eau: Syncing GNUstep menu for key window: %@", keyWindow);
          [self setMenu: menu forWindow: keyWindow];
        }
      else
        {
          NSDebugLog(@"Eau: No key window available for menu change notification");
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
      NSDebugLog(@"Eau: Exception unregistering application menu: %@", exception);
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
      NSDebugLog(@"Eau: Window became key, syncing GNUstep menu: %@", window);
      [self setMenu: mainMenu forWindow: window];
    }
  else
    {
      NSDebugLog(@"Eau: Window became key but no main menu available: %@", window);
    }
}

+ (NSColor *) controlStrokeColor
{

  return [NSColor colorWithCalibratedRed: 0.4
                                   green: 0.4
                                    blue: 0.4
                                   alpha: 1];
}

- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state
{
  NSColor	*backgroundColor = [self buttonColorInCell: cell forState: state];
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];
  [buttonBackgroundGradient drawInBezierPath: path angle: -90];
  [strokeColorButton setStroke];
  [path setLineWidth: 1];
  [path stroke];
}

- (void) sendMenu:(NSWindow*)w {

  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  NSDebugLog(@"Eau: sendMenu");
  NSMenu *m = [menuByWindowId objectForKey:windowId];

  @try
    {
      // NSDebugLog(@"Eau: Calling updateMenuForWindow on Menu.app server proxy");
      NSDictionary *menuData = [self _serializeMenu:m];

      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForWindow:windowId
							   menuData:menuData
							 clientName:[self _menuClientName]];
      NSDebugLog(@"Eau: Successfully sent menu update to Menu.app");
      NSDebugLog(@"Eau: Updated GNUstep menu for window %@", windowId);
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"Eau: Exception sending GNUstep menu: %@, falling back to standard menu", exception);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
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
      NSDebugLog(@"Eau: Pushed application-level menu to Menu.app");
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"Eau: Exception pushing application-level menu: %@", exception);
    }
}

/* Menu.app asks the client to re-push its application-level menu (startup
   recovery, or after the app's last window closed). */
- (oneway void)requestApplicationMenuUpdate
{
  NSDebugLog(@"Eau: requestApplicationMenuUpdate called");

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

      // Serialize with index paths — includes fresh enabled/state after [menu update]
      NSDictionary *menuData = [self _serializeMenuWithIndexPaths:menu];
      if (menuData)
        {
          [(id<GSGNUstepMenuServer>)menuServerProxy
            updateMenuEnabledStatesForWindow:windowId
                                    menuData:menuData
                                  clientName:[self _menuClientName]];
          NSDebugLog(@"Eau: Pushed enabled states for window %@", windowId);
        }
    }
  @catch (NSException *exception)
    {
      NSDebugLog(@"Eau: Exception pushing enabled states: %@", exception);
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
          NSDebugLog(@"Eau: Exception pushing application enabled states: %@", exception);
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

// NSMenuDidSendActionNotification — fired after ANY action is sent through a
// menu item, including keyboard shortcuts that match menu items.  We push
// updated enabled/state to Menu.app so the menu bar is always current.
// This is more efficient than a polling timer — we only push when something
// might have changed.
- (void)menuDidSendAction:(NSNotification *)note
{
  (void)note;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _pushMenuEnabledStates];
  });
}

// NSMenuDidEndTrackingNotification — fired after any menu tracking session
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
      NSDebugLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      NSDebugLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (m == nil || [m numberOfItems] == 0)
    {
      NSDebugLog(@"Eau: Menu is nil or empty (items=%ld)", (long)[m numberOfItems]);
      BOOL hadMenu = ([menuByWindowId objectForKey:windowId] != nil);
      [menuByWindowId removeObjectForKey:windowId];

      if (hadMenu && [self _ensureMenuServerConnection])
        {
          @try
            {
              NSDebugLog(@"Eau: Unregistering window %@ from Menu.app", windowId);
              [(id<GSGNUstepMenuServer>)menuServerProxy unregisterWindow:windowId
                                                                clientName:[self _menuClientName]];
            }
          @catch (NSException *exception)
            {
              NSDebugLog(@"Eau: Exception unregistering window %@: %@", windowId, exception);
              NSDebugLog(@"Eau: Exception unregistering window %@: %@", windowId, exception);
            }
        }

      NSDebugLog(@"Eau: Menu is nil or empty, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  // NSDebugLog(@"Eau: Storing menu in cache for windowId=%@, menu has %ld items", windowId, (long)[m numberOfItems]);
  // TOM: i believe this is redundant
  // [m update];

  [menuByWindowId setObject:m forKey:windowId];

  if (![self _ensureMenuClientRegistered])
    {
      NSDebugLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      NSDebugLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (![self _ensureMenuServerConnection])
    {
      NSDebugLog(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      NSDebugLog(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
      return;
    }

  // Rate-limited menu updating (coalesced to avoid messaging freed objects)
  gPendingMenuWindow = w;
  if (!gPendingMenuUpdate)
    {
      gPendingMenuUpdate = YES;
      [self performSelector: @selector(eau_sendPendingMenu)
                 withObject: nil
                 afterDelay: 0.1];
    }
}

- (void) eau_sendPendingMenu
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
      NSLog(@"Eau: dropping menu action: window %@, index path %@", windowId, indexPath);
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
          NSLog(@"Eau: dropping menu action %@: no menu for window %@", indexPath, windowId);
          return;
        }
    }

  NSMenuItem *menuItem = [self _menuItemForIndexPath:indexPath inMenu:menu];
  if (menuItem == nil)
    {
      NSLog(@"Eau: dropping menu action: no item at %@ in the menu of window %@", indexPath, windowId);
      return;
    }

  /* The enabled flag is only as fresh as the last validation, which AppKit
     runs after X events.  An action that arrived over DO (e.g. Select All from
     Menu.app) changes the state without such an event, so a Copy chosen right
     after it would be dropped as disabled. */
  [[menuItem menu] update];
  if (![menuItem isEnabled])
    {
      NSLog(@"Eau: dropping menu action '%@': item is disabled", [menuItem title]);
      return;
    }

  SEL action = [menuItem action];
  id target = [menuItem target];

  if (action == NULL)
    {
      NSLog(@"Eau: dropping menu action '%@': item has no action", [menuItem title]);
      return;
    }

  [NSApp sendAction:action to:target from:menuItem];
}

- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath forWindow:(NSNumber *)windowId
{
  NSDebugLog(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  NSDebugLog(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  
  NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                           indexPath ?: [NSArray array], @"indexPath",
                           windowId ?: [NSNumber numberWithUnsignedInt:0], @"windowId",
                           nil];

  if (![NSThread isMainThread])
    {
      /* Logged because the action then depends on the libdispatch main
         queue being drained by the run loop; if it never runs, this line is
         the only trace. */
      NSLog(@"Eau: menu action %@ arrived off the main thread, handing it to the main queue", indexPath);
      dispatch_async(dispatch_get_main_queue(), ^{
        [self _performMenuActionFromIPC:payload];
      });
      return;
    }

  NSDebugLog(@"Eau: On main thread, calling _performMenuActionFromIPC directly");
  [self _performMenuActionFromIPC:payload];
}

// Recursively collect @[title, enabled, state] triples from a menu tree.
// Returns a flat NSArray — no nested dictionaries — so it copies over DO
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
  NSDebugLog(@"Eau: validateMenuStateForWindow called - windowId: %@", windowId);

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
      NSDebugLog(@"Eau: validateMenuStateForWindow: no menu found for window %@", windowId);
      return nil;
    }

  // Recursively validate ALL items before collecting states
  [self _recursiveMenuUpdate:menu];

  // Return a flat array of @[title, enabled, state] triples.
  // No nested dictionaries — copies over DO in one batch instantly.
  NSArray *flat = [self _collectFlatStates:menu];
  NSDebugLog(@"Eau: validateMenuStateForWindow: returning %lu flat items for window %@",
         (unsigned long)[flat count], windowId);
  return flat;
}

- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId
{
  NSDebugLog(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);
  NSDebugLog(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);

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
      NSDebugLog(@"Eau: requestMenuUpdateForWindow: pushing menu for window %@", windowId);
      [self setMenu:[NSApp mainMenu] forWindow:targetWindow];
    }
  else
    {
      NSDebugLog(@"Eau: requestMenuUpdateForWindow: no window found for %@, cannot push", windowId);
    }
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  // Always use Menu.app IPC when available
  if ((menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu))
    {
      NSDebugLog(@"Eau: Modifying menu rect for GNUstep IPC: hiding menu bar");
      return NSZeroRect;
    }
  
  NSDebugLog(@"Eau: Using standard menu rect (Menu.app %@)", menuServerAvailable ? @"available" : @"unavailable");
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  // Always use Menu.app IPC when available
  if ((menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu))
    {
      NSDebugLog(@"Eau: Proposing menu visibility NO for GNUstep IPC");
      return NO;
    }

  NSDebugLog(@"Eau: Proposing standard menu visibility %@ (Menu.app %@)",
         visibility ? @"YES" : @"NO", menuServerAvailable ? @"available" : @"unavailable");
  return [super proposedVisibility: visibility forMenu: menu];
}

/**
 * Override GSTheme's keyForKeyEquivalent: to convert GNUstep key equivalent
 * strings to Mac-style symbols with Shift shown after Command.
 *
 * The NSMenuItemCell _keyEquivalentString produces strings like "/#s" where
 * modifiers are single-character codes (^=Control, +=Alternate, /=Shift, #=Command)
 * ordered Control → Alternate → Shift → Command → Key.
 *
 * This override converts to Mac Unicode symbols (⌃⌥⌘⇧) and reorders to
 * Control → Alternate → Command → Shift → Key.
 */
- (NSString *) keyForKeyEquivalent: (NSString *)aString
{
  if (!aString || [aString length] == 0)
    {
      return aString;
    }

  // Parse standard GNUstep modifier codes from the front of the string
  //
  // Format: [^][+][/][#]key
  //         ^ = Control   += Alternate/Option   /= Shift   # = Command
  NSUInteger pos = 0;
  NSUInteger len = [aString length];
  BOOL hasControl = NO;
  BOOL hasAlternate = NO;
  BOOL hasShift = NO;
  BOOL hasCommand = NO;

  while (pos < len)
    {
      unichar ch = [aString characterAtIndex: pos];
      if (ch == '^')   { hasControl = YES;  pos++; }
      else if (ch == '+') { hasAlternate = YES; pos++; }
      else if (ch == '/') { hasShift = YES;    pos++; }
      else if (ch == '#') { hasCommand = YES;  pos++; }
      else { break; }
    }

  // Remaining characters are the key name
  NSString *key = [aString substringFromIndex: pos];

  // Build Mac-style string: Control ⌃ → Option ⌥ → Command ⌘ → Shift ⇧ → Key
  NSMutableString *result = [NSMutableString string];
  if (hasControl)  { [result appendString: @"⌃"]; }
  if (hasAlternate){ [result appendString: @"⌥"]; }
  if (hasCommand)  { [result appendString: @"⌘"]; }
  if (hasShift)    { [result appendString: @"⇧"]; }

  // Uppercase single-letter keys
  if ([key length] == 1)
    {
      unichar ch = [key characterAtIndex: 0];
      if (ch >= 'a' && ch <= 'z')
        {
          key = [key uppercaseString];
        }
    }

  [result appendString: key];
  return result;
}

@end
