// NSMenuView+Rik.m
// Rik Theme NSMenuView Extensions

#import "Rik.h"
#import "NSMenuView+Rik.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

// Store original method implementation
static IMP originalLocationForSubmenuIMP = NULL;

// Our replacement locationForSubmenu: method
static NSPoint swizzled_locationForSubmenu(id self, SEL _cmd, NSMenu *aSubmenu) {
  NSMenuView *menuView = (NSMenuView *)self;
  
  // Call the original implementation - it correctly calculates Y position
  NSPoint originalPoint = ((NSPoint (*)(id, SEL, NSMenu*))originalLocationForSubmenuIMP)(self, _cmd, aSubmenu);
  
  // If this menu view itself is horizontal (the menu bar), use original positioning entirely
  if ([menuView isHorizontal]) {
    return originalPoint;
  }
  
  // For vertical dropdown menus, adjust only the X position to remove overlap
  // Keep the original Y position which correctly aligns with the parent item
  NSWindow *window = [menuView window];
  if (!window) {
    return originalPoint;
  }
  
  NSRect frame = [window frame];
  
  // X position: right edge of parent menu window (just touching, no overlap)
  CGFloat xPos = NSMaxX(frame);
  
  // Y position: use the original calculation which correctly handles item position
  CGFloat yPos = originalPoint.y;
  
  NSLog(@"NSMenuView+Rik: Adjusted submenu position from {%.1f, %.1f} to {%.1f, %.1f}",
        originalPoint.x, originalPoint.y, xPos, yPos);
  
  return NSMakePoint(xPos, yPos);
}

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void) {
  NSLog(@"NSMenuView+Rik: Constructor called - setting up swizzling");
  
  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass) {
    NSLog(@"NSMenuView+Rik: ERROR - NSMenuView class not found");
    return;
  }
  
  // Swizzle locationForSubmenu:
  SEL locationSelector = sel_registerName("locationForSubmenu:");
  Method locationMethod = class_getInstanceMethod(menuViewClass, locationSelector);
  if (locationMethod) {
    originalLocationForSubmenuIMP = method_getImplementation(locationMethod);
    method_setImplementation(locationMethod, (IMP)swizzled_locationForSubmenu);
    NSLog(@"NSMenuView+Rik: Successfully swizzled locationForSubmenu: method");
  } else {
    NSLog(@"NSMenuView+Rik: ERROR - Could not find locationForSubmenu: method");
  }
}

@implementation NSMenuView (RikTheme)
@end
