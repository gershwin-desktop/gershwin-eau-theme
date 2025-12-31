// NSMenuView+Eau.m
// Eau Theme NSMenuView Extensions

#import "Eau.h"
#import "NSMenuView+Eau.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

@implementation NSMenuView (EauTheme)

- (NSPoint)eau_locationForSubmenu:(NSMenu *)aSubmenu
{
  NSLog(@"NSMenuView+Eau: eau_locationForSubmenu: called for submenu %@", aSubmenu);

  NSMenuView *menuView = (NSMenuView *)self;

  // Call the original implementation - it correctly calculates Y position.
  // After swizzling, -eau_locationForSubmenu: points to the original
  // -locationForSubmenu: implementation.
  NSPoint originalPoint = [self eau_locationForSubmenu:aSubmenu];

  // If this menu view itself is horizontal (the menu bar), use original positioning entirely
  if ([menuView isHorizontal]) {
    NSLog(@"NSMenuView+Eau: Menu is horizontal, using original submenu position {%.1f, %.1f}",
          originalPoint.x, originalPoint.y);
    return originalPoint;
  }

  // For vertical dropdown menus, adjust only the X position to remove overlap
  // Keep the original Y position which correctly aligns with the parent item
  NSWindow *window = [menuView window];
  if (!window) {
    NSLog(@"NSMenuView+Eau: No window for menu view, using original submenu position {%.1f, %.1f}",
          originalPoint.x, originalPoint.y);
    return originalPoint;
  }

  NSRect frame = [window frame];

  // X position: right edge of parent menu window (just touching, no overlap)
  CGFloat xPos = NSMaxX(frame);

  // Y position: use the original calculation which correctly handles item position
  CGFloat yPos = originalPoint.y;

  NSLog(@"NSMenuView+Eau: Adjusted submenu position from {%.1f, %.1f} to {%.1f, %.1f}",
        originalPoint.x, originalPoint.y, xPos, yPos);

  return NSMakePoint(xPos, yPos);
}

@end

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void) {
  // NSLog(@"NSMenuView+Eau: Constructor called - setting up swizzling");

  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass) {
    NSLog(@"NSMenuView+Eau: ERROR - NSMenuView class not found");
    return;
  }

  // Swizzle locationForSubmenu: with eau_locationForSubmenu:
  SEL originalSelector = sel_registerName("locationForSubmenu:");
  SEL swizzledSelector = @selector(eau_locationForSubmenu:);

  Method originalMethod = class_getInstanceMethod(menuViewClass, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(menuViewClass, swizzledSelector);

  if (!originalMethod) {
    NSLog(@"NSMenuView+Eau: ERROR - Could not find original locationForSubmenu: method");
    return;
  }

  if (!swizzledMethod) {
    NSLog(@"NSMenuView+Eau: ERROR - Could not find eau_locationForSubmenu: method on NSMenuView");
    return;
  }

  // Avoid double-swizzling: if the IMPs are already the same, do nothing.
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP) {
    NSLog(@"NSMenuView+Eau: Swizzling skipped - implementations already identical");
    return;
  }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  // NSLog(@"NSMenuView+Eau: Successfully swizzled locationForSubmenu: with eau_locationForSubmenu:");
}
