#import "Eau.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <Foundation/NSConnection.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"

@protocol GSGNUstepMenuServer
- (oneway void)updateMenuForWindow:(NSNumber *)windowId
                          menuData:(NSDictionary *)menuData
                        clientName:(NSString *)clientName;
- (oneway void)unregisterWindow:(NSNumber *)windowId
                       clientName:(NSString *)clientName;
@end

@implementation Eau

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

  NSLog(@"Eau: Registered GNUstep menu client as %@ with receive port %@", clientName, [menuClientConnection receivePort]);
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
      menuServerAvailable = NO;
    }

  if (menuServerProxy != nil)
    {
      return menuServerAvailable;
    }

  NSConnection *connection = [NSConnection connectionWithRegisteredName:@"org.gnustep.Gershwin.MenuServer"
                                                                   host:nil];
  if (connection == nil)
    {
      menuServerAvailable = NO;
      return NO;
    }

  menuServerConnection = connection;

  id proxy = [menuServerConnection rootProxy];
  if (proxy != nil)
    {
      [proxy setProtocolForProxy:@protocol(GSGNUstepMenuServer)];
      menuServerProxy = proxy;
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
  menuServerAvailable = NO;
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
  menuServerAvailable = NO;
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

- (void)setMenu:(NSMenu*)m forWindow:(NSWindow*)w
{
  // Reduce verbose logging for frequent menu updates
  static NSMutableDictionary *lastMenuUpdateTime = nil;
  static NSMutableDictionary *lastMenuPointer = nil;
  static NSMutableDictionary *firstMenuSent = nil;
  static NSTimeInterval startupTime = 0;
  if (!lastMenuUpdateTime) {
    lastMenuUpdateTime = [[NSMutableDictionary alloc] init];
  }
  if (!lastMenuPointer) {
    lastMenuPointer = [[NSMutableDictionary alloc] init];
  }
  if (!firstMenuSent) {
    firstMenuSent = [[NSMutableDictionary alloc] init];
  }
  if (startupTime == 0) {
    startupTime = [NSDate timeIntervalSinceReferenceDate];
  }

  NSNumber *windowId = [self _windowIdentifierForWindow:w];
  if (windowId == nil)
    {
      NSLog(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      EAULOG(@"Eau: Could not resolve window identifier, using standard menu for window: %@", w);
      [super setMenu: m forWindow: w];
      return;
    }
  // NSLog(@"Eau: Resolved windowId=%@", windowId);

  // Debounce repeated updates for the same menu during startup
  NSNumber *lastTime = [lastMenuUpdateTime objectForKey:windowId];
  NSValue *lastPtr = [lastMenuPointer objectForKey:windowId];
  // During the first 15 seconds after startup, send only the first menu update per window
  if (([NSDate timeIntervalSinceReferenceDate] - startupTime) < 15.0) {
    if ([firstMenuSent objectForKey:windowId]) {
      NSLog(@"Eau: Suppressing repeated menu updates during startup for window %@", windowId);
      return;
    }
  }

  if (lastTime) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval prev = [lastTime doubleValue];
    if ((now - prev) < 2.0) {
      if (lastPtr && [lastPtr pointerValue] == (__bridge void *)m) {
        NSLog(@"Eau: Skipping duplicate menu update for window %@ (debounced)", windowId);
        return;
      }
      NSLog(@"Eau: Throttling rapid menu updates for window %@", windowId);
      return;
    }
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
      [super setMenu: m forWindow: w];
      return;
    }

  // NSLog(@"Eau: Storing menu in cache for windowId=%@, menu has %ld items", windowId, (long)[m numberOfItems]);
  [menuByWindowId setObject:m forKey:windowId];

  if (![self _ensureMenuClientRegistered])
    {
      NSLog(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      EAULOG(@"Eau: Failed to register GNUstep menu client, using standard menu for window: %@", w);
      [super setMenu: m forWindow: w];
      return;
    }

  if (![self _ensureMenuServerConnection])
    {
      NSLog(@"Eau: GNUstep menu server unavailable, using standard menu for window: %@", w);
      EAULOG(@"Eau: GNUstep menu server unavailable, using standard menu for window: %@", w);
      [super setMenu: m forWindow: w];
      return;
    }

  @try
    {
      // NSLog(@"Eau: Calling updateMenuForWindow on Menu.app server proxy");
      NSDictionary *menuData = [self _serializeMenu:m];
      // NSLog(@"Eau: Serialized menu data: %@", menuData);
      [(id<GSGNUstepMenuServer>)menuServerProxy updateMenuForWindow:windowId
                                                          menuData:menuData
                                                        clientName:[self _menuClientName]];
      // NSLog(@"Eau: Successfully sent menu update to Menu.app");
      EAULOG(@"Eau: Updated GNUstep menu for window %@", windowId);

      // Record the update time and menu pointer for debouncing
      [lastMenuUpdateTime setObject:@([NSDate timeIntervalSinceReferenceDate]) forKey:windowId];
      [lastMenuPointer setObject:[NSValue valueWithPointer:(__bridge const void *)m] forKey:windowId];
      [firstMenuSent setObject:@YES forKey:windowId];
    }
  @catch (NSException *exception)
    {
      EAULOG(@"Eau: Exception sending GNUstep menu: %@, falling back to standard menu", exception);
      [super setMenu: m forWindow: w];
    }
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
      [self performSelectorOnMainThread:@selector(_performMenuActionFromIPC:)
                             withObject:payload
                          waitUntilDone:NO];
      return;
    }

  EAULOG(@"Eau: On main thread, calling _performMenuActionFromIPC directly");
  [self _performMenuActionFromIPC:payload];
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  // Always use Menu.app IPC when available
  if (menuServerAvailable && ([NSApp mainMenu] == menu))
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
  if (menuServerAvailable && ([NSApp mainMenu] == menu))
    {
      EAULOG(@"Eau: Proposing menu visibility NO for GNUstep IPC");
      return NO;
    }
  
  EAULOG(@"Eau: Proposing standard menu visibility %@ (Menu.app %@)", 
         visibility ? @"YES" : @"NO", menuServerAvailable ? @"available" : @"unavailable");
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
