// NSMenuView+Rik.m
// Rik Theme NSMenuView Extensions - Swizzling for dropdown menu padding

#import "Rik.h"
#import "NSMenuView+Rik.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

// Store original method implementations
static IMP originalSizeToFitIMP = NULL;
static IMP originalRectOfItemAtIndexIMP = NULL;

// Our replacement sizeToFit method - adds padding to vertical menus
static void swizzled_sizeToFit(id self, SEL _cmd) {
  NSMenuView *menuView = (NSMenuView *)self;
  
  // Call original implementation first
  ((void (*)(id, SEL))originalSizeToFitIMP)(self, _cmd);
  
  // Only add padding to vertical (dropdown) menus, not horizontal menu bar
  if (![menuView isHorizontal]) {
    NSRect frame = [menuView frame];
    
    frame.size.width += RIK_MENU_ITEM_PADDING;
    [menuView setFrameSize: frame.size];
  }
}

// Our replacement rectOfItemAtIndex: method - adds padding to cell rect width
static NSRect swizzled_rectOfItemAtIndex(id self, SEL _cmd, NSInteger index) {
  NSMenuView *menuView = (NSMenuView *)self;
  
  // Call original implementation
  NSRect originalRect = ((NSRect (*)(id, SEL, NSInteger))originalRectOfItemAtIndexIMP)(self, _cmd, index);
  
  // Only add padding to vertical (dropdown) menus, not horizontal menu bar
  if (![menuView isHorizontal]) {
    originalRect.size.width += RIK_MENU_ITEM_PADDING;
  }
  
  return originalRect;
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
  
  // Swizzle sizeToFit to add padding to vertical menus
  SEL sizeToFitSelector = sel_registerName("sizeToFit");
  Method sizeToFitMethod = class_getInstanceMethod(menuViewClass, sizeToFitSelector);
  if (sizeToFitMethod) {
    originalSizeToFitIMP = method_getImplementation(sizeToFitMethod);
    method_setImplementation(sizeToFitMethod, (IMP)swizzled_sizeToFit);
    NSLog(@"NSMenuView+Rik: Successfully swizzled sizeToFit method");
  } else {
    NSLog(@"NSMenuView+Rik: ERROR - Could not find sizeToFit method");
  }
  
  // Swizzle rectOfItemAtIndex: to return padded rect
  SEL rectOfItemSelector = sel_registerName("rectOfItemAtIndex:");
  Method rectOfItemMethod = class_getInstanceMethod(menuViewClass, rectOfItemSelector);
  if (rectOfItemMethod) {
    originalRectOfItemAtIndexIMP = method_getImplementation(rectOfItemMethod);
    method_setImplementation(rectOfItemMethod, (IMP)swizzled_rectOfItemAtIndex);
    NSLog(@"NSMenuView+Rik: Successfully swizzled rectOfItemAtIndex: method");
  } else {
    NSLog(@"NSMenuView+Rik: ERROR - Could not find rectOfItemAtIndex: method");
  }
}

@implementation NSMenuView (RikTheme)
@end
