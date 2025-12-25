// NSMenuView+Rik.m
// Rik Theme NSMenuView Extensions

#import "Rik.h"
#import "NSMenuView+Rik.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

@implementation NSMenuView (RikTheme)

// This method will hold the original implementation after swizzling
- (NSPoint)RIK_originalLocationForSubmenu:(NSMenu *)aSubmenu {
  NSMenuView *menuView = self;
  
  // After swizzling, this calls the original implementation
  NSPoint originalPoint = [self RIK_originalLocationForSubmenu:aSubmenu];
  
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
  
  RIKLOG(@"NSMenuView+Rik: Adjusted submenu position from {%.1f, %.1f} to {%.1f, %.1f}",
        originalPoint.x, originalPoint.y, xPos, yPos);
  
  return NSMakePoint(xPos, yPos);
}

// +load is called when the class is loaded, guaranteed to run after the class is ready
+ (void)load {
  RIKLOG(@"NSMenuView+Rik: +load called - setting up swizzling");
  
  Class menuViewClass = [NSMenuView class];
  if (!menuViewClass) {
    RIKLOG(@"NSMenuView+Rik: ERROR - NSMenuView class not found");
    return;
  }
  
  // Swizzle locationForSubmenu:
  SEL originalSelector = @selector(locationForSubmenu:);
  SEL swizzledSelector = @selector(RIK_originalLocationForSubmenu:);
  
  Method originalMethod = class_getInstanceMethod(menuViewClass, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(menuViewClass, swizzledSelector);
  
  if (originalMethod && swizzledMethod) {
    // Exchange implementations - this is thread-safe
    method_exchangeImplementations(originalMethod, swizzledMethod);
    RIKLOG(@"NSMenuView+Rik: Successfully swizzled locationForSubmenu: method");
  } else {
    RIKLOG(@"NSMenuView+Rik: ERROR - Could not find locationForSubmenu: method");
  }
}

@end
