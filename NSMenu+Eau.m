/*
   NSMenu+Eau.m

   Swizzles NSMenu methods to enable NSMacintoshInterfaceStyle support
   with upstream (unmodified) libs-gui.

   This allows the Eau theme to:
   1. Receive notifications when the main menu changes
   2. Control menu visibility (hide in-app menu bar for global menu)
*/

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>

#import "Eau.h"

@implementation NSMenu (Eau)

#pragma mark - Swizzled Methods

/**
 * Swizzled -menuChanged implementation.
 *
 * The original menuChanged propagates up the menu hierarchy and sets
 * _menu.mainMenuChanged when reaching the main menu. Upstream only
 * handles this flag for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when the
 * change reaches the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_menuChanged
{
  // Call original implementation (handles propagation and flag setting)
  [self eau_menuChanged];

  // If this is the main menu and using Macintosh style, post notification
  if ([NSApp mainMenu] == self)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -setMain: implementation.
 *
 * The original setMain: configures the menu as the application's main menu.
 * Upstream only calls updateAllWindowsWithMenu: for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when a menu
 * becomes the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_setMain:(BOOL)isMain
{
  // Call original implementation
  [self eau_setMain:isMain];

  // If becoming main menu and using Macintosh style, post notification
  if (isMain)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -display implementation.
 *
 * The original display method shows the menu window unconditionally.
 * While upstream has proposedVisibility:forMenu: in _isVisible, this
 * is only used for querying state, not controlling display.
 *
 * This swizzle checks proposedVisibility:forMenu: before displaying,
 * allowing the theme to hide the in-app menu bar when using a global
 * menu bar (Menu.app).
 */
- (void)eau_display
{
  // Let theme control visibility
  // The theme's proposedVisibility:forMenu: returns NO for the main menu
  // when Menu.app is available, hiding the in-app menu bar
  if (![[GSTheme theme] proposedVisibility:YES forMenu:self])
    {
      return;
    }

  // Call original implementation
  [self eau_display];
}

@end

#pragma mark - Swizzling Setup

/**
 * Helper function to swizzle a method on NSMenu.
 *
 * @param menuClass The NSMenu class
 * @param originalSel The original selector to swizzle
 * @param swizzledSel The replacement selector
 * @param methodName Human-readable method name for logging
 */
static void swizzleNSMenuMethod(Class menuClass,
                                SEL originalSel,
                                SEL swizzledSel,
                                const char *methodName)
{
  Method originalMethod = class_getInstanceMethod(menuClass, originalSel);
  Method swizzledMethod = class_getInstanceMethod(menuClass, swizzledSel);

  if (!originalMethod)
    {
      EAULOG(@"Eau: Cannot swizzle NSMenu -%s: original method not found", methodName);
      return;
    }

  if (!swizzledMethod)
    {
      EAULOG(@"Eau: Cannot swizzle NSMenu -%s: swizzled method not found", methodName);
      return;
    }

  // Prevent double-swizzling on bundle reload
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP)
    {
      EAULOG(@"Eau: NSMenu -%s already swizzled, skipping", methodName);
      return;
    }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  EAULOG(@"Eau: Swizzled NSMenu -%s for Macintosh menu support", methodName);
}

/**
 * Constructor function that runs when the theme bundle loads.
 *
 * Installs method swizzles on NSMenu to enable NSMacintoshInterfaceStyle
 * support with upstream libs-gui.
 */
__attribute__((constructor))
static void initNSMenuSwizzling(void)
{
  Class menuClass = objc_getClass("NSMenu");
  if (!menuClass)
    {
      EAULOG(@"Eau: Failed to get NSMenu class for swizzling");
      return;
    }

  EAULOG(@"Eau: Installing NSMenu swizzles for Macintosh interface style support");

  // Swizzle -menuChanged
  // Posts notification when menu changes reach the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(menuChanged),
                      @selector(eau_menuChanged),
                      "menuChanged");

  // Swizzle -setMain:
  // Posts notification when a menu becomes the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(setMain:),
                      @selector(eau_setMain:),
                      "setMain:");

  // Swizzle -display
  // Allows theme to hide menu window via proposedVisibility:forMenu:
  swizzleNSMenuMethod(menuClass,
                      @selector(display),
                      @selector(eau_display),
                      "display");
}
