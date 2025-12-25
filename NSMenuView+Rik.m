// NSMenuView+Rik.m
// Rik Theme NSMenuView Extensions - Swizzling for dropdown menu padding

#import "Rik.h"
#import "NSMenuView+Rik.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

// Store original method implementations
static IMP originalSizeToFitIMP = NULL;

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
    
    NSLog(@"NSMenuView+Rik: swizzled_sizeToFit - added %.0fpx padding, new width: %.1f", 
           RIK_MENU_ITEM_PADDING, frame.size.width);
  }
}

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void) {
  NSLog(@"NSMenuView+Rik: Constructor called - setting up sizeToFit swizzling");
  
  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass) {
    NSLog(@"NSMenuView+Rik: ERROR - NSMenuView class not found");
    return;
  }
  
  // Swizzle sizeToFit to add padding to vertical menus
  SEL sizeToFitSelector = sel_registerName("sizeToFit");
  
  Method originalMethod = class_getInstanceMethod(menuViewClass, sizeToFitSelector);
  if (originalMethod) {
    // Save the original implementation
    originalSizeToFitIMP = method_getImplementation(originalMethod);
    
    // Replace with our implementation
    method_setImplementation(originalMethod, (IMP)swizzled_sizeToFit);
    
    NSLog(@"NSMenuView+Rik: Successfully swizzled sizeToFit method (original IMP: %p)", originalSizeToFitIMP);
  } else {
    NSLog(@"NSMenuView+Rik: ERROR - Could not find sizeToFit method");
  }
}

@implementation NSMenuView (RikTheme)
@end
