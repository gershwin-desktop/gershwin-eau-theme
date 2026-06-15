#import "Eau.h"

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortNameServer.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"
#import "EauMenuRelaunchManager.h"

static BOOL gForceExternalMenuByEnv = NO;

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

+ (void)load
{
  gForceExternalMenuByEnv = EauEnvironmentContainsAppMenuToken();
  if (gForceExternalMenuByEnv)
    {
      NSLog(@"Eau: appmenu token detected in environment, forcing external menu mode");
    }

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
      return YES;
    }

  menuClientConnection = [[NSConnection alloc] init];
  [menuClientConnection setRootObject:self];
  menuClientReceivePort = [menuClientConnection receivePort];
  
  // Set up the connection to receive messages
  [[NSRunLoop currentRunLoop] addPort:menuClientReceivePort
                              forMode:NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addPort:menuClientReceivePort
                              forMode:NSModalPanelRunLoopMode];
  [[NSRunLoop currentRunLoop] addPort:menuClientReceivePort
                              forMode:NSEventTrackingRunLoopMode];
  [[NSRunLoop currentRunLoop] addPort:menuClientReceivePort
                              forMode:NSRunLoopCommonModes];

  NSString *clientName = [self _menuClientName];
  BOOL registered = [menuClientConnection registerName:clientName];
  if (!registered)
    {
      EAULOG(@"Eau: Failed to register GNUstep menu client name: %@", clientName);
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
      menuClientConnection = nil;
      return NO;
    }

  EAULOG(@"Eau: Registered GNUstep menu client as %@ with receive port %@", clientName, [menuClientConnection receivePort]);
  EAULOG(@"Eau: Registered GNUstep menu client as %@ with receive port added to run loop", clientName);
  [[NSNotificationCenter defaultCenter] removeObserver:self name:NSConnectionDidDieNotification object:menuClientConnection];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_menuClientConnectionDidDie:)
                                               name:NSConnectionDidDieNotification
                                             object:menuClientConnection];
  return YES;
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
      EAULOG(@"Eau: Connected to GNUstep menu server");
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
  if (menu == nil)
    {
      return nil;
    }

  // TOM: update 'enabled' states
  [menu update];

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

  return [NSDictionary dictionaryWithObjectsAndKeys:
                      ([menu title] ?: @""), @"title",
                      items, @"items",
                      nil];
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
  EAULOG(@"Eau: >>> initWithBundle ENTRY (before super init)");
  if ((self = [super initWithBundle:bundle]) != nil)
    {
      EAULOG(@"Eau: >>> initWithBundle after super init, self=%p", self);
      EAULOG(@"Eau: Initializing theme with bundle: %@", bundle);
      
      
      menuByWindowId = [[NSMutableDictionary alloc] init];
      menuServerAvailable = NO;
      menuServerConnected = NO;

      // Snapshot the current Menu process launch details so restarts can match.
      [[EauMenuRelaunchManager sharedManager] captureMenuProcessSnapshotIfAvailable];

      // Register as a GNUstep menu client so Menu.app can call back for actions
      [self _ensureMenuClientRegistered];

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

      // After any menu selection finishes, push updated enabled/state values
      // to Menu.app so items like Copy/Paste reflect the new app state without
      // requiring the user to open a submenu first.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidEndTracking:)
               name:NSMenuDidEndTrackingNotification
             object:nil];

      EAULOG(@"Eau: GNUstep menu IPC initialized (Menu.app %@)",
             menuServerAvailable ? @"available" : @"unavailable");

      // Ensure alternating row background color is visible in Eau theme
      // Note: System color list may be read-only, so we wrap in try-catch
      EAULOG(@"Eau: >>> About to check system color list");
      @try
        {
          NSColorList *systemColors = [NSColorList colorListNamed: @"System"];
          EAULOG(@"Eau: >>> System color list: %p, isEditable: %d",
                 systemColors, systemColors ? [systemColors isEditable] : -1);
          if (systemColors != nil && [systemColors isEditable])
            {
              EAULOG(@"Eau: >>> Setting alternateRowBackgroundColor");
              // Light gray with a touch of blue
              [systemColors setColor: [NSColor colorWithCalibratedRed: 0.94
                                                                 green: 0.95
                                                                  blue: 0.97
                                                                 alpha: 1.0]
                               forKey: @"alternateRowBackgroundColor"];
              EAULOG(@"Eau: >>> alternateRowBackgroundColor set successfully");
            }
          else
            {
              EAULOG(@"Eau: >>> Skipping color list modification (nil or not editable)");
            }
        }
      @catch (NSException *exception)
        {
          EAULOG(@"Eau: Could not set alternating row color: %@", [exception reason]);
        }
      // After ANY action is sent through a menu item (including keyboard
      // shortcuts matched to menu items), push updated enabled/state values
      // to Menu.app.  This is more efficient than a timer — we only push
      // when something might have changed.
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(menuDidSendAction:)
               name:NSMenuDidSendActionNotification
             object:nil];

      EAULOG(@"Eau: >>> initWithBundle EXIT");
    }
  return self;
}    

- (void) dealloc
{
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
  NSLog(@"Eau: Menu client connection died");
  EAULOG(@"Eau: Menu client connection died");
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
  menuClientConnection = nil;
}

- (void)_menuServerConnectionDidDie:(NSNotification *)notification
{
  NSLog(@"Eau: Menu server connection died");
  EAULOG(@"Eau: Menu server connection died");
  menuServerConnection = nil;
  menuServerProxy = nil;
  menuServerConnected = NO;
  // Automatic Menu.app restart disabled.
  // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];
  
  if ([NSApp mainMenu] == menu)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          EAULOG(@"Eau: Syncing GNUstep menu for key window: %@", keyWindow);
          [self setMenu: menu forWindow: keyWindow];
        }
      else
        {
          EAULOG(@"Eau: No key window available for menu change notification");
        }
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
      EAULOG(@"Eau: Window became key, syncing GNUstep menu: %@", window);
      [self setMenu: mainMenu forWindow: window];
    }
  else
    {
      EAULOG(@"Eau: Window became key but no main menu available: %@", window);
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
  NSLog(@"Eau: sendMenu");
  NSMenu *m = [menuByWindowId objectForKey:windowId];

  @try
    {
      // NSLog(@"Eau: Calling updateMenuForWindow on Menu.app server proxy");
      NSDictionary *menuData = [self _serializeMenu:m];

      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForWindow:windowId
							   menuData:menuData
							 clientName:[self _menuClientName]];
      NSLog(@"Eau: Successfully sent menu update to Menu.app");
      EAULOG(@"Eau: Updated GNUstep menu for window %@", windowId);
    }
  @catch (NSException *exception)
    {
      EAULOG(@"Eau: Exception sending GNUstep menu: %@, falling back to standard menu", exception);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
    }
  

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
      // Run NSMenuValidation so items get fresh enabled/state values before we
      // push them to Menu.app.  Without this, [item isEnabled] returns stale
      // values set at the time the menu was last serialized.
      [menu update];

      // Serialize with index paths — includes fresh enabled/state after [menu update]
      NSDictionary *menuData = [self _serializeMenuWithIndexPaths:menu];
      if (menuData)
        {
          [(id<GSGNUstepMenuServer>)menuServerProxy
            updateMenuEnabledStatesForWindow:windowId
                                    menuData:menuData
                                  clientName:[self _menuClientName]];
          EAULOG(@"Eau: Pushed enabled states for window %@", windowId);
        }
    }
  @catch (NSException *exception)
    {
      EAULOG(@"Eau: Exception pushing enabled states: %@", exception);
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
      NSLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      EAULOG(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (m == nil || [m numberOfItems] == 0)
    {
      NSLog(@"Eau: Menu is nil or empty (items=%ld)", (long)[m numberOfItems]);
      BOOL hadMenu = ([menuByWindowId objectForKey:windowId] != nil);
      [menuByWindowId removeObjectForKey:windowId];

      if (hadMenu && [self _ensureMenuServerConnection])
        {
          @try
            {
              NSLog(@"Eau: Unregistering window %@ from Menu.app", windowId);
              [(id<GSGNUstepMenuServer>)menuServerProxy unregisterWindow:windowId
                                                                clientName:[self _menuClientName]];
            }
          @catch (NSException *exception)
            {
              NSLog(@"Eau: Exception unregistering window %@: %@", windowId, exception);
              EAULOG(@"Eau: Exception unregistering window %@: %@", windowId, exception);
            }
        }

      EAULOG(@"Eau: Menu is nil or empty, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  // NSLog(@"Eau: Storing menu in cache for windowId=%@, menu has %ld items", windowId, (long)[m numberOfItems]);
  // TOM: i believe this is redundant
  // [m update];

  [menuByWindowId setObject:m forKey:windowId];

  if (![self _ensureMenuClientRegistered])
    {
      NSLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      EAULOG(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      if (!gForceExternalMenuByEnv)
        {
          [super setMenu: m forWindow: w];
        }
      return;
    }

  if (![self _ensureMenuServerConnection])
    {
      NSLog(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      EAULOG(@"Eau: GNUstep menu server unavailable, automatic Menu.app restart disabled for window: %@", w);
      // [[EauMenuRelaunchManager sharedManager] relaunchMenuProcessIfSnapshotAvailable];
      return;
    }

  // Rate-limited menu updating
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendMenu:) object:w];
  [self performSelector:@selector(sendMenu:) withObject:w afterDelay:0.1];
}

- (void)_performMenuActionFromIPC:(NSDictionary *)info
{
  NSLog(@"Eau: _performMenuActionFromIPC called with info: %@", info);
  EAULOG(@"Eau: _performMenuActionFromIPC called with info: %@", info);
  
  NSNumber *windowId = [info objectForKey:@"windowId"];
  NSArray *indexPath = [info objectForKey:@"indexPath"];

  if (windowId == nil || indexPath == nil)
    {
      EAULOG(@"Eau: Invalid GNUstep menu action payload");
      return;
    }

  NSMenu *menu = [menuByWindowId objectForKey:windowId];
  if (menu == nil)
    {
      EAULOG(@"Eau: No menu cached for window %@", windowId);
      EAULOG(@"Eau: Available windows in cache: %@", [menuByWindowId allKeys]);
      
      // Fallback: if we only have one cached menu, use it
      // This handles the case where the window ID doesn't match exactly
      // (e.g., different X11 window ID than expected)
      if ([menuByWindowId count] == 1)
        {
          menu = [[menuByWindowId allValues] firstObject];
          EAULOG(@"Eau: Using fallback menu (only one cached menu)");
        }
      else if ([menuByWindowId count] > 0)
        {
          // Multiple windows cached - use the first one (usually the main window)
          menu = [[menuByWindowId allValues] firstObject];
          EAULOG(@"Eau: Using fallback menu (first of %lu cached menus)", (unsigned long)[menuByWindowId count]);
        }
      
      if (menu == nil)
        {
          EAULOG(@"Eau: No cached menu available for fallback");
          return;
        }
    }

  EAULOG(@"Eau: Found menu for window %@, looking up item at path %@", windowId, indexPath);
  
  NSMenuItem *menuItem = [self _menuItemForIndexPath:indexPath inMenu:menu];
  if (menuItem == nil)
    {
      EAULOG(@"Eau: Menu item not found for window %@ path %@", windowId, indexPath);
      return;
    }

  EAULOG(@"Eau: Found menu item '%@', checking if enabled", [menuItem title]);
  
  if (![menuItem isEnabled])
    {
      EAULOG(@"Eau: Menu item '%@' disabled, ignoring", [menuItem title]);
      return;
    }

  SEL action = [menuItem action];
  id target = [menuItem target];
  
  EAULOG(@"Eau: Menu item '%@' - action: %@, target: %@", [menuItem title], NSStringFromSelector(action), target);
  
  if (action == NULL)
    {
      EAULOG(@"Eau: Menu item '%@' has no action", [menuItem title]);
      return;
    }

  EAULOG(@"Eau: Sending action %@ to target %@ from menu item '%@'", NSStringFromSelector(action), target, [menuItem title]);
  BOOL handled = [NSApp sendAction:action to:target from:menuItem];
  NSLog(@"Eau: sendAction returned %@ for menu item '%@'", handled ? @"YES" : @"NO", [menuItem title]);
  EAULOG(@"Eau: Action sent successfully");
}























// JSON variants for compatibility






- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath forWindow:(NSNumber *)windowId
{
  NSLog(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  EAULOG(@"Eau: activateMenuItemAtPath called - indexPath: %@, windowId: %@", indexPath, windowId);
  
  NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                           indexPath ?: [NSArray array], @"indexPath",
                           windowId ?: [NSNumber numberWithUnsignedInt:0], @"windowId",
                           nil];

  if (![NSThread isMainThread])
    {
      EAULOG(@"Eau: Not on main thread, dispatching to main thread");
      dispatch_async(dispatch_get_main_queue(), ^{
        [self _performMenuActionFromIPC:payload];
      });
      return;
    }

  EAULOG(@"Eau: On main thread, calling _performMenuActionFromIPC directly");
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
  EAULOG(@"Eau: validateMenuStateForWindow called - windowId: %@", windowId);

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

  if (!menu)
    {
      EAULOG(@"Eau: validateMenuStateForWindow: no menu found for window %@", windowId);
      return nil;
    }

  // Run NSMenuValidation so items get fresh enabled/state values
  [menu update];

  // Return a flat array of @[title, enabled, state] triples.
  // No nested dictionaries — copies over DO in one batch instantly.
  NSArray *flat = [self _collectFlatStates:menu];
  EAULOG(@"Eau: validateMenuStateForWindow: returning %lu flat items for window %@",
         (unsigned long)[flat count], windowId);
  return flat;
}

- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId
{
  NSLog(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);
  EAULOG(@"Eau: requestMenuUpdateForWindow called - windowId: %@", windowId);

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
      EAULOG(@"Eau: requestMenuUpdateForWindow: pushing menu for window %@", windowId);
      [self setMenu:[NSApp mainMenu] forWindow:targetWindow];
    }
  else
    {
      EAULOG(@"Eau: requestMenuUpdateForWindow: no window found for %@, cannot push", windowId);
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
      EAULOG(@"Eau: Modifying menu rect for GNUstep IPC: hiding menu bar");
      return NSZeroRect;
    }
  
  EAULOG(@"Eau: Using standard menu rect (Menu.app %@)", menuServerAvailable ? @"available" : @"unavailable");
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  // Always use Menu.app IPC when available
  if ((menuServerAvailable || gForceExternalMenuByEnv) && ([NSApp mainMenu] == menu))
    {
      EAULOG(@"Eau: Proposing menu visibility NO for GNUstep IPC");
      return NO;
    }
  
  EAULOG(@"Eau: Proposing standard menu visibility %@ (Menu.app %@)", 
         visibility ? @"YES" : @"NO", menuServerAvailable ? @"available" : @"unavailable");
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
