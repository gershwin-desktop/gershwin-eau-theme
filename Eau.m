#import "Eau.h"

#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSPortNameServer.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"

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

// Expose UIBridge-friendly API from theme so the UIBridge server can talk to the
// theme process directly (avoids needing to inject an agent into each app).
#import "../gershwin-components/UIBridge/Common/UIBridgeProtocol.h"

@protocol GSGNUstepMenuServer
- (oneway void)updateMenuForWindow:(NSNumber *)windowId
                          menuData:(NSDictionary *)menuData
                        clientName:(NSString *)clientName;
- (oneway void)unregisterWindow:(NSNumber *)windowId
                       clientName:(NSString *)clientName;
@end

// Dedicated UIBridge proxy object to expose the Eau theme's UIBridgeProtocol methods
// This is needed because Distributed Objects requires explicit protocol conformance
@interface EauUIBridgeProxy : NSObject <UIBridgeProtocol>
{
  Eau *theme;
}
- (id)initWithTheme:(Eau *)t;
@end

@interface Eau () <UIBridgeProtocol>
@end

@implementation EauUIBridgeProxy

- (id)initWithTheme:(Eau *)t
{
  if ((self = [super init]) != nil) {
    theme = t;
  }
  return self;
}

// Forward all protocol methods to the Eau theme
- (bycopy NSString *)rootObjectsJSON {
  return [theme rootObjectsJSON];
}

- (bycopy NSString *)detailsForObjectJSON:(NSString *)objID {
  return [theme detailsForObjectJSON:objID];
}

- (bycopy NSString *)fullTreeForObjectJSON:(NSString *)objID {
  return [theme fullTreeForObjectJSON:objID];
}

- (bycopy NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
  return [theme invokeSelectorJSON:selectorName onObject:objID withArgs:args];
}

- (bycopy id)rootObjects {
  return [theme rootObjects];
}

- (bycopy id)detailsForObject:(NSString *)objID {
  return [theme detailsForObject:objID];
}

- (bycopy id)fullTreeForObject:(NSString *)objID {
  return [theme fullTreeForObject:objID];
}

- (bycopy id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args {
  return [theme invokeSelector:selectorName onObject:objID withArgs:args];
}

- (bycopy NSArray *)listMenus {
  return [theme listMenus];
}

- (bycopy NSString *)listMenusJSON {
  return [theme listMenusJSON];
}

- (BOOL)invokeMenuItem:(NSString *)objID {
  return [theme invokeMenuItem:objID];
}

@end


// Connection delegate to enable multi-threading on child connections
@interface EauConnectionDelegate : NSObject
@end

@implementation EauConnectionDelegate
- (NSConnection *)connection:(NSConnection *)parentConnection didConnect:(NSConnection *)newConnection
{
    // Enable multi-threading on all child connections immediately
    [newConnection enableMultipleThreads];
    [newConnection setIndependentConversationQueueing:YES];
    NSLog(@"Eau: [Delegate] Enabled multi-threading on new connection: %@ (parent: %@)", newConnection, parentConnection);
    return newConnection;
}

- (BOOL)connection:(NSConnection *)parentConnection shouldMakeNewConnection:(NSConnection *)newConnection
{
    // Enable multi-threading before the connection becomes active
    [newConnection enableMultipleThreads];
    [newConnection setIndependentConversationQueueing:YES];
    NSLog(@"Eau: [Delegate] shouldMakeNewConnection - enabled multi-threading on: %@", newConnection);
    return YES;
}
@end

static EauConnectionDelegate *gUIBridgeConnectionDelegate = nil;

// Connection used to expose UIBridgeProtocol methods from theme (per-PID service)
static NSConnection *gUIBridgeThemeConnection = nil;
static EauUIBridgeProxy *gUIBridgeProxy = nil;

@implementation Eau
+ (void)load
{
  NSLog(@"Eau: +load called");
  // Schedule UIBridge service registration after a delay to ensure run loop is active
  // Using dispatch_after ensures this runs even if performSelector isn't processed
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self _registerUIBridgeService:nil];
  });
}

+ (void)_handleNewConnection:(NSNotification *)notification
{
  NSConnection *conn = [notification object];
  // Enable multi-threading on all new connections to handle cross-process requests
  [conn enableMultipleThreads];
  [conn setIndependentConversationQueueing:YES];
  NSLog(@"Eau: Enabled multi-threading on new connection: %@", conn);
}

// Static variable to hold the shared Eau instance for UIBridge
static Eau *gSharedEauInstance = nil;

+ (void)_registerUIBridgeService:(id)unused
{
  // Check if we have a valid Eau instance
  if (!gSharedEauInstance) {
    // Try to get from GSTheme
    id themeObj = (id)[GSTheme theme];
    if ([themeObj isKindOfClass:[Eau class]]) {
      gSharedEauInstance = (Eau *)themeObj;
    } else {
      NSLog(@"Eau: _registerUIBridgeService called but no Eau instance available yet (got %@)", [themeObj class]);
      return;
    }
  }
  
  // Already registered?
  if (gUIBridgeThemeConnection) {
    NSLog(@"Eau: UIBridge service already registered, skipping");
    return;
  }
  
  pid_t pid = [[NSProcessInfo processInfo] processIdentifier];
  // Register per-PID service so each app has its own unique UIBridge service
  NSString *name = [NSString stringWithFormat:@"org.gershwin.Gershwin.Theme.UIBridge.%d", pid];
  NSLog(@"Eau: Registering per-PID UIBridge theme service: %@", name);
  
  @try {
    NSLog(@"Eau: Theme object class: %@, responds to listMenus: %d", 
          [gSharedEauInstance class], 
          (int)[gSharedEauInstance respondsToSelector:@selector(listMenus)]);
    
    // Create a proxy object that explicitly implements UIBridgeProtocol
    gUIBridgeProxy = [[EauUIBridgeProxy alloc] initWithTheme:gSharedEauInstance];
    NSLog(@"Eau: Created UIBridge proxy: %@", gUIBridgeProxy);
    
    // Create connection delegate to handle child connections
    gUIBridgeConnectionDelegate = [[EauConnectionDelegate alloc] init];
    
    gUIBridgeThemeConnection = [[NSConnection alloc] init];
    NSLog(@"Eau: Connection created - receivePort: %@, sendPort: %@", 
          [gUIBridgeThemeConnection receivePort], 
          [gUIBridgeThemeConnection sendPort]);
    [gUIBridgeThemeConnection setRootObject:gUIBridgeProxy];
    // Set delegate to enable multi-threading on child connections BEFORE they process messages
    [gUIBridgeThemeConnection setDelegate:gUIBridgeConnectionDelegate];
    // Allow independent request handling for thread safety
    [gUIBridgeThemeConnection setIndependentConversationQueueing:YES];
    // Enable multiple threads to allow handling requests from external processes
    [gUIBridgeThemeConnection enableMultipleThreads];
    
    // Also keep notification handler as backup
    [[NSNotificationCenter defaultCenter] addObserver:[self class]
                                             selector:@selector(_handleNewConnection:)
                                                 name:NSConnectionDidInitializeNotification
                                               object:nil];
    
    // Add ports to the main runloop BEFORE registration
    NSPort *recvPort = [gUIBridgeThemeConnection receivePort];
    NSPort *sendPort = [gUIBridgeThemeConnection sendPort];
    [[NSRunLoop mainRunLoop] addPort:recvPort forMode:NSDefaultRunLoopMode];
    [[NSRunLoop mainRunLoop] addPort:recvPort forMode:NSModalPanelRunLoopMode];
    [[NSRunLoop mainRunLoop] addPort:recvPort forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop mainRunLoop] addPort:recvPort forMode:NSRunLoopCommonModes];
    if (sendPort && sendPort != recvPort) {
      [[NSRunLoop mainRunLoop] addPort:sendPort forMode:NSDefaultRunLoopMode];
      [[NSRunLoop mainRunLoop] addPort:sendPort forMode:NSModalPanelRunLoopMode];
      [[NSRunLoop mainRunLoop] addPort:sendPort forMode:NSEventTrackingRunLoopMode];
      [[NSRunLoop mainRunLoop] addPort:sendPort forMode:NSRunLoopCommonModes];
    }
    
    NSLog(@"Eau: Ports added to main runloop");
    
    BOOL ok = [gUIBridgeThemeConnection registerName:name];
    NSLog(@"Eau: registerName returned: %d", ok);
    if (ok) {
      NSLog(@"Eau: Successfully registered per-PID UIBridge theme service: %@", name);
    } else {
      NSLog(@"Eau: Failed to register per-PID UIBridge service as %@", name);
      gUIBridgeThemeConnection = nil;
    }
  } @catch (NSException *e) {
    NSLog(@"Eau: Exception during UIBridge registration: %@", e);
    gUIBridgeThemeConnection = nil;
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
      
      // Set shared instance for UIBridge service
      gSharedEauInstance = self;
      
      menuByWindowId = [[NSMutableDictionary alloc] init];
      menuServerAvailable = NO;

      // Register as a GNUstep menu client so Menu.app can call back for actions
      [self _ensureMenuClientRegistered];

      // Try to connect to Menu.app's GNUstep menu server (may not be running yet)
      [self _ensureMenuServerConnection];
      
      // Register UIBridge service so server can query menus from theme
      NSLog(@"Eau: Registering UIBridge service from initWithBundle");
      [[self class] _registerUIBridgeService:nil];

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

#pragma mark - UIBridgeProtocol (exposes only the frontmost/active window)

- (bycopy NSArray *)listMenus
{
  __block NSMutableArray *result = nil;
  
  void (^block)(void) = ^{
    result = [NSMutableArray array];
    
    // Get the key (frontmost) window
    NSWindow *keyWindow = [NSApp keyWindow];
    if (!keyWindow && [NSApp windows] && [[NSApp windows] count] > 0) {
      // Fallback to first window if no key window
      keyWindow = [[NSApp windows] objectAtIndex:0];
    }
    
    if (keyWindow) {
      NSNumber *winId = [self _windowIdentifierForWindow:keyWindow];
      if (winId) {
        NSMenu *m = [menuByWindowId objectForKey:winId];
        if (!m && [menuByWindowId count] > 0) {
          // Fallback: use the first cached menu
          m = [[menuByWindowId allValues] firstObject];
        }
        if (m) {
          NSDictionary *menuData = [self _serializeMenuWithIndexPaths:m];
          [result addObject:@{ @"windowId": winId, @"menu": menuData }];
        }
      }
    }

    // Also include the application's main menu (Application menu) as a global fallback
    NSMenu *appMainMenu = [NSApp mainMenu];
    if (appMainMenu) {
      NSLog(@"Eau: Including application mainMenu as fallback");
      NSDictionary *appMenuData = [self _serializeMenuWithIndexPaths:appMainMenu];
      // Use nil windowId to indicate it's the global app menu
      [result addObject:@{ @"windowId": [NSNull null], @"menu": appMenuData }];
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSArray array];
}

- (bycopy NSString *)listMenusJSON
{
  NSArray *menus = [self listMenus];
  NSData *d = [NSJSONSerialization dataWithJSONObject:menus options:0 error:nil];
  if (!d) return @"null";
  return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

- (BOOL)invokeMenuItem:(NSString *)objID
{
  if (!objID || ![objID hasPrefix:@"menuitem:"]) return NO;
  
  // Expected format: menuitem:<windowId>:<idx0>.<idx1>...
  NSArray *parts = [objID componentsSeparatedByString:@":"];
  if ([parts count] < 3) return NO;
  NSString *windowStr = parts[1];
  NSString *pathStr = parts[2];
  NSNumber *windowId = @([windowStr longLongValue]);
  NSArray *components = [pathStr componentsSeparatedByString:@"."];
  NSMutableArray *indexPath = [NSMutableArray array];
  for (NSString *c in components) { [indexPath addObject:@([c integerValue])]; }
  
  // Call into existing menu activation code from main thread
  __block BOOL handled = NO;
  if ([NSThread isMainThread]) {
    @try {
      [self activateMenuItemAtPath:indexPath forWindow:windowId];
      handled = YES;
    } @catch (NSException *e) {
      NSLog(@"Eau: Exception in invokeMenuItem %@: %@", objID, e);
      handled = NO;
    }
  } else {
    dispatch_sync(dispatch_get_main_queue(), ^{
      @try {
        [self activateMenuItemAtPath:indexPath forWindow:windowId];
        handled = YES;
      } @catch (NSException *e) {
        NSLog(@"Eau: Exception in invokeMenuItem %@: %@", objID, e);
        handled = NO;
      }
    });
  }
  
  return handled;
}

- (bycopy id)rootObjects
{
  __block NSDictionary *result = nil;
  
  void (^block)(void) = ^{
    NSMutableArray *wins = [NSMutableArray array];
    for (NSWindow *w in [NSApp windows]) {
      NSMutableDictionary *d = [NSMutableDictionary dictionary];
      d[@"object_id"] = [self _objectIDForObject:w];
      d[@"class"] = NSStringFromClass([w class]);
      d[@"title"] = [w title] ?: @"";
      d[@"frame"] = NSStringFromRect([w frame]);
      d[@"windowNumber"] = @([w windowNumber]);
      d[@"hidden"] = @(![w isVisible]);
      [wins addObject:d];
    }
    result = @{
      @"NSApp": [self _objectIDForObject:NSApp],
      @"windows": wins
    };
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: @{ @"NSApp": @"", @"windows": @[] };
}

#pragma mark - UIBridge Object Serialization Helpers

- (NSString *)_objectIDForObject:(id)obj
{
  if (!obj) return @"";
  return [NSString stringWithFormat:@"objc:%p", obj];
}

- (id)_objectForID:(NSString *)objID
{
  if (![objID hasPrefix:@"objc:"]) return nil;
  unsigned long long ptrVal;
  NSScanner *scanner = [NSScanner scannerWithString:[objID substringFromIndex:5]];
  if ([scanner scanHexLongLong:&ptrVal]) {
    return (__bridge id)(void *)ptrVal;
  }
  return nil;
}

- (id)_serializeObject:(id)obj detailed:(BOOL)detailed depth:(int)depth
{
  if (!obj || obj == [NSNull null] || depth < 0) return [NSNull null];
  if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) return obj;
  
  NSString *className = @"Unknown";
  @try { className = NSStringFromClass([obj class]); } @catch (NSException *e) { }
  
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  dict[@"object_id"] = [self _objectIDForObject:obj];
  dict[@"class"] = className;
  
  // Handle NSView
  if ([obj isKindOfClass:[NSView class]]) {
    NSView *view = (NSView *)obj;
    NSRect frame = [view frame];
    dict[@"frame"] = NSStringFromRect(frame);
    dict[@"hidden"] = @([view isHidden]);
    
    // Get title for buttons
    if ([view respondsToSelector:@selector(title)]) {
      id title = [view performSelector:@selector(title)];
      if (title && ![title isEqual:@""]) dict[@"title"] = title;
    }
    // Get string value for text fields
    if ([view isKindOfClass:[NSTextField class]]) {
      NSTextField *tf = (NSTextField *)view;
      dict[@"stringValue"] = [tf stringValue] ?: @"";
      dict[@"string"] = [tf stringValue] ?: @"";
    }
    
    // Computed screen coordinates
    @try {
      if ([view window]) {
        NSRect winRect = [view convertRect:[view bounds] toView:nil];
        dict[@"window_frame"] = NSStringFromRect(winRect);
        
        NSRect screenRect = [[view window] convertRectToScreen:winRect];
        dict[@"screen_frame"] = NSStringFromRect(screenRect);
      }
    } @catch (NSException *e) { }
    
    // Control-specific properties
    if ([view isKindOfClass:[NSControl class]]) {
      NSControl *control = (NSControl *)view;
      dict[@"enabled"] = @([control isEnabled]);
      dict[@"tag"] = @([control tag]);
    }
    
    // Button-specific properties
    if ([view isKindOfClass:[NSButton class]]) {
      NSButton *button = (NSButton *)view;
      dict[@"keyEquivalent"] = [button keyEquivalent] ?: @"";
      dict[@"keyModifiers"] = @([button keyEquivalentModifierMask]);
    }
    
    // Recurse subviews if detailed
    if (detailed && depth > 0) {
      NSMutableArray *subviews = [NSMutableArray array];
      for (NSView *sub in [view subviews]) {
        [subviews addObject:[self _serializeObject:sub detailed:YES depth:depth - 1]];
      }
      dict[@"subviews"] = subviews;
    }
  }
  
  // Handle NSWindow
  if ([obj isKindOfClass:[NSWindow class]]) {
    NSWindow *win = (NSWindow *)obj;
    dict[@"title"] = [win title] ?: @"";
    dict[@"frame"] = NSStringFromRect([win frame]);
    dict[@"hidden"] = @(![win isVisible]);
    
    if (detailed && depth > 0) {
      dict[@"contentView"] = [self _serializeObject:[win contentView] detailed:YES depth:depth - 1];
    }
  }
  
  // Handle NSApplication
  if ([obj isKindOfClass:[NSApplication class]]) {
    NSApplication *app = (NSApplication *)obj;
    if (detailed && depth > 0) {
      NSMutableArray *wins = [NSMutableArray array];
      for (NSWindow *win in [app windows]) {
        [wins addObject:[self _serializeObject:win detailed:YES depth:depth - 1]];
      }
      dict[@"windows"] = wins;
    }
  }
  
  // Handle NSMenu
  if ([obj isKindOfClass:[NSMenu class]]) {
    NSMenu *menu = (NSMenu *)obj;
    dict[@"title"] = [menu title] ?: @"";
    if (detailed && depth > 0) {
      NSMutableArray *items = [NSMutableArray array];
      for (NSMenuItem *item in [menu itemArray]) {
        [items addObject:[self _serializeObject:item detailed:YES depth:depth - 1]];
      }
      dict[@"items"] = items;
    }
  }
  
  // Handle NSMenuItem
  if ([obj isKindOfClass:[NSMenuItem class]]) {
    NSMenuItem *item = (NSMenuItem *)obj;
    dict[@"title"] = [item title] ?: @"";
    dict[@"enabled"] = @([item isEnabled]);
    dict[@"hasSubmenu"] = @([item hasSubmenu]);
    dict[@"isSeparator"] = @([item isSeparatorItem]);
    if ([item action]) dict[@"action"] = NSStringFromSelector([item action]);
    if ([item keyEquivalent]) dict[@"keyEquivalent"] = [item keyEquivalent];
    dict[@"keyModifiers"] = @([item keyEquivalentModifierMask]);
    dict[@"tag"] = @([item tag]);
    dict[@"state"] = @([item state]);
    if ([item hasSubmenu] && detailed && depth > 0) {
      dict[@"submenu"] = [self _serializeObject:[item submenu] detailed:YES depth:depth - 1];
    }
  }
  
  return dict;
}

- (bycopy id)detailsForObject:(NSString *)objID
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    // Handle menuitem: IDs
    if (objID && [objID hasPrefix:@"menuitem:"]) {
      NSArray *parts = [objID componentsSeparatedByString:@":"];
      if ([parts count] >= 3) {
        NSNumber *windowId = @([parts[1] longLongValue]);
        NSString *pathStr = parts[2];
        NSArray *components = [pathStr componentsSeparatedByString:@"."];
        NSMutableArray *indexPath = [NSMutableArray array];
        for (NSString *c in components) [indexPath addObject:@([c integerValue])];
        NSMenu *menu = [menuByWindowId objectForKey:windowId];
        if (!menu && [menuByWindowId count] > 0) menu = [[menuByWindowId allValues] firstObject];
        NSMenuItem *it = [self _menuItemForIndexPath:indexPath inMenu:menu];
        if (it) {
          result = [self _serializeObject:it detailed:YES depth:2];
          return;
        }
      }
    }
    
    // Handle objc: IDs
    id obj = [self _objectForID:objID];
    if (obj) {
      result = [self _serializeObject:obj detailed:YES depth:2];
    } else {
      result = [NSNull null];
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

- (bycopy id)fullTreeForObject:(NSString *)objID
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    id obj = nil;
    if (!objID || [objID length] == 0 || [objID isEqualToString:@"NSApp"]) {
      obj = NSApp;
    } else {
      obj = [self _objectForID:objID];
    }
    
    if (obj) {
      result = [self _serializeObject:obj detailed:YES depth:15];
    } else {
      // Fallback to menu tree for backwards compatibility
      result = @{ @"menus": [self listMenus] };
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

- (bycopy id)invokeSelector:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args
{
  __block id result = nil;
  
  void (^block)(void) = ^{
    // Handle invokeMenuItemByID: special case
    if (selectorName && [selectorName isEqualToString:@"invokeMenuItemByID:"] && args && [args count] > 0) {
      NSString *menuId = args[0];
      BOOL ok = [self invokeMenuItem:menuId];
      result = ok ? @YES : @NO;
      return;
    }
    
    // General selector invocation
    id obj = [self _objectForID:objID];
    if (!obj) {
      result = @{ @"error": @{ @"code": @-32000, @"message": @"Object not found" } };
      return;
    }
    
    SEL sel = NSSelectorFromString(selectorName);
    if (![obj respondsToSelector:sel]) {
      result = @{ @"error": @{ @"code": @-32601, @"message": @"Selector not found" } };
      return;
    }
    
    NSMethodSignature *sig = [obj methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:obj];
    [inv setSelector:sel];
    
    if (args && [args isKindOfClass:[NSArray class]]) {
      for (NSUInteger i = 0; i < [args count]; i++) {
        if (i + 2 >= [sig numberOfArguments]) break;
        id arg = args[i];
        if (arg == [NSNull null]) arg = nil;
        [inv setArgument:&arg atIndex:i + 2];
      }
    }
    
    @try {
      [inv invoke];
      
      if ([sig methodReturnLength] > 0) {
        const char *retType = [sig methodReturnType];
        if (retType[0] == '@' || retType[0] == '#') {
          id retVal = nil;
          [inv getReturnValue:&retVal];
          result = [self _serializeObject:retVal detailed:NO depth:1];
        } else {
          result = @"OK";
        }
      } else {
        result = @"OK";
      }
    } @catch (NSException *e) {
      result = @{ @"error": @{ @"code": @-32001, @"message": [e description] } };
    }
  };
  
  if ([NSThread isMainThread]) {
    block();
  } else {
    dispatch_sync(dispatch_get_main_queue(), block);
  }
  
  return result ?: [NSNull null];
}

// JSON variants for compatibility
- (bycopy NSString *)rootObjectsJSON { NSData *d = [NSJSONSerialization dataWithJSONObject:[self rootObjects] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)detailsForObjectJSON:(NSString *)objID { NSData *d = [NSJSONSerialization dataWithJSONObject:[self detailsForObject:objID] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)fullTreeForObjectJSON:(NSString *)objID { NSData *d = [NSJSONSerialization dataWithJSONObject:[self fullTreeForObject:objID] options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }
- (bycopy NSString *)invokeSelectorJSON:(NSString *)selectorName onObject:(NSString *)objID withArgs:(NSArray *)args { id r = [self invokeSelector:selectorName onObject:objID withArgs:args]; NSData *d = [NSJSONSerialization dataWithJSONObject:r options:0 error:nil]; return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"null"; }


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
