#import "Eau.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"

// cache the DBusMenu bundle's principal class
static Class _menuRegistryClass;
  
@implementation Eau

- (BOOL)_isDBusAvailable
{
  // Check if D-Bus session bus address is set and valid
  const char *dbusSessionBusAddress = getenv("DBUS_SESSION_BUS_ADDRESS");
  
  if (dbusSessionBusAddress == NULL || strlen(dbusSessionBusAddress) == 0)
    {
      EAULOG(@"Eau: No DBUS_SESSION_BUS_ADDRESS environment variable set, D-Bus unavailable");
      return NO;
    }
  
  // Basic validation of the D-Bus address format
  NSString *addressString = [NSString stringWithUTF8String:dbusSessionBusAddress];
  if (![addressString hasPrefix:@"unix:"] && ![addressString hasPrefix:@"tcp:"])
    {
      EAULOG(@"Eau: Invalid DBUS_SESSION_BUS_ADDRESS format: %@, D-Bus unavailable", addressString);
      return NO;
    }
  
  EAULOG(@"Eau: D-Bus available with address: %@", addressString);
  return YES;
}

- (Class)_findDBusMenuRegistryClass
{
  NSString   *path;
  NSBundle   *bundle;
  NSArray    *paths = NSSearchPathForDirectoriesInDomains(
                        NSLibraryDirectory, NSAllDomainsMask, YES);
  NSUInteger  count = [paths count];

  if (Nil != _menuRegistryClass)
    return _menuRegistryClass;

  // Don't attempt to load D-Bus bundle if D-Bus is not available
  if (![self _isDBusAvailable])
    {
      EAULOG(@"Eau: D-Bus not available, skipping DBusMenu bundle loading");
      return Nil;
    }

  while (count-- > 0)
    {
      path = [paths objectAtIndex:count];
      path = [path stringByAppendingPathComponent:@"Bundles"];
      path = [path stringByAppendingPathComponent:@"DBusMenu"];
      path = [path stringByAppendingPathExtension:@"bundle"];
      bundle = [NSBundle bundleWithPath:path];
      if (bundle)
        {
          if ((_menuRegistryClass = [bundle principalClass]) != Nil)
            {
              EAULOG(@"Eau: Successfully loaded DBusMenu bundle from: %@", path);
              break;
            }
        }
    }
  
  if (_menuRegistryClass == Nil)
    {
      EAULOG(@"Eau: Could not find or load DBusMenu bundle, continuing without D-Bus menu support");
    }
  
  return _menuRegistryClass;
}

- (id)initWithBundle:(NSBundle *)bundle
{
  if ((self = [super initWithBundle:bundle]) != nil)
    {
      EAULOG(@"Eau: Initializing theme with bundle: %@", bundle);
      
      // Try to initialize D-Bus menu registry, but continue gracefully if it fails
      @try 
        {
          Class menuRegistryClass = [self _findDBusMenuRegistryClass];
          if (menuRegistryClass != Nil)
            {
              menuRegistry = [[menuRegistryClass alloc] init];
              if (menuRegistry != nil)
                {
                  EAULOG(@"Eau: D-Bus menu registry initialized successfully");
                  
                  // Add notification observer for menu changes only if D-Bus is available
                  [[NSNotificationCenter defaultCenter] 
                    addObserver: self
                       selector: @selector(macintoshMenuDidChange:)
                           name: @"NSMacintoshMenuDidChangeNotification"
                         object: nil];
                  
                  EAULOG(@"Eau: Menu change notification observer added");
                }
              else
                {
                  EAULOG(@"Eau: Failed to initialize D-Bus menu registry instance, continuing without D-Bus");
                }
            }
          else
            {
              EAULOG(@"Eau: No D-Bus menu registry class available, continuing without D-Bus");
            }
        }
      @catch (NSException *exception)
        {
          EAULOG(@"Eau: Exception during D-Bus initialization: %@, continuing without D-Bus", exception);
          menuRegistry = nil;
        }
      
      EAULOG(@"Eau: Theme initialization completed (D-Bus %@)", menuRegistry ? @"enabled" : @"disabled");

      // Ensure alternating row background color is visible in Eau theme
      NSColorList *systemColors = [NSColorList colorListNamed: @"System"];
      if (systemColors != nil)
        {
          // Light gray with a touch of blue
          [systemColors setColor: [NSColor colorWithCalibratedRed: 0.94 
                                                             green: 0.95 
                                                              blue: 0.97 
                                                             alpha: 1.0]
                           forKey: @"alternateRowBackgroundColor"];
        }
    }
  return self;
}    

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  // Only handle menu changes if D-Bus is available
  if (menuRegistry == nil)
    {
      EAULOG(@"Eau: Menu change notification received but D-Bus is not available, ignoring");
      return;
    }
  
  NSMenu *menu = [notification object];
  
  if (([NSApp mainMenu] == menu) && menuRegistry != nil)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          EAULOG(@"Eau: Setting D-Bus menu for key window: %@", keyWindow);
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

  return RETAIN([NSColor colorWithCalibratedRed: 0.4
                                          green: 0.4
                                           blue: 0.4
                                          alpha: 1]);
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
  if (nil != menuRegistry && m != nil && [m numberOfItems] > 0)
    {
      @try 
        {
          EAULOG(@"Eau: Setting D-Bus menu for window: %@", w);
          [menuRegistry setMenu: m forWindow: w];
          EAULOG(@"Eau: Successfully set D-Bus menu for window");
        }
      @catch (NSException *exception)
        {
          EAULOG(@"Eau: Exception setting D-Bus menu: %@, falling back to standard menu", exception);
          [super setMenu: m forWindow: w];
        }
    }
  else if (nil == menuRegistry)
    {
      EAULOG(@"Eau: No D-Bus menu registry, using standard menu for window: %@", w);
      [super setMenu: m forWindow: w];
    }
  else
    {
      EAULOG(@"Eau: Menu is nil or empty, not setting D-Bus menu for window: %@", w);
    }
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      EAULOG(@"Eau: Modifying menu rect for Macintosh style with D-Bus: hiding menu bar");
      return NSZeroRect;
    }
  
  EAULOG(@"Eau: Using standard menu rect (D-Bus %@)", menuRegistry ? @"available" : @"unavailable");
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      EAULOG(@"Eau: Proposing menu visibility NO for Macintosh style with D-Bus");
      return NO;
    }
  
  EAULOG(@"Eau: Proposing standard menu visibility %@ (D-Bus %@)", 
         visibility ? @"YES" : @"NO", menuRegistry ? @"available" : @"unavailable");
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
