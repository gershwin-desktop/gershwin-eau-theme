#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "AppearanceMetrics.h"

// Category on NSFont used for method swizzling
@interface NSFont (EauSwizzling)
+ (NSFont *)eau_menuBarFontOfSize:(CGFloat)fontSize;
+ (NSFont *)eau_menuFontOfSize:(CGFloat)fontSize;
@end

@implementation NSFont (EauSwizzling)

// Swizzled implementation for menuBarFontOfSize: - returns font with HIG size
+ (NSFont *)eau_menuBarFontOfSize:(CGFloat)fontSize {
  // Call the original menuBarFontOfSize: to get the base font
  NSFont *baseFont = [self eau_menuBarFontOfSize:fontSize];
  
  // Create a new font with HIG size using the font descriptor
  NSFontDescriptor *descriptor = [baseFont fontDescriptor];
  NSFont *sizedFont = [NSFont fontWithDescriptor:descriptor size:[METRICS_FONT_SYSTEM_REGULAR_13 pointSize]];
  
  NSDebugLog(@"NSFont+Eau: menuBarFontOfSize: returning font with size %.1f (was %.1f)", [sizedFont pointSize], [baseFont pointSize]);
  
  return sizedFont;
}

// Swizzled implementation for menuFontOfSize: - returns font with HIG size
+ (NSFont *)eau_menuFontOfSize:(CGFloat)fontSize {
  // Call the original menuFontOfSize: to get the base font
  NSFont *baseFont = [self eau_menuFontOfSize:fontSize];
  
  // Create a new font with HIG size using the font descriptor
  NSFontDescriptor *descriptor = [baseFont fontDescriptor];
  NSFont *sizedFont = [NSFont fontWithDescriptor:descriptor size:[METRICS_FONT_SYSTEM_REGULAR_13 pointSize]];
  
  NSDebugLog(@"NSFont+Eau: menuFontOfSize: returning font with size %.1f (was %.1f)", [sizedFont pointSize], [baseFont pointSize]);
  
  return sizedFont;
}

@end

// Constructor to set up swizzling
__attribute__((constructor))
static void initFontSwizzling(void) {
  Class fontClass = [NSFont class];
  if (!fontClass) {
    NSLog(@"NSFont+Eau: ERROR - NSFont class not found");
    return;
  }

  // Swizzle menuBarFontOfSize:
  SEL menuBarFontSelector = sel_registerName("menuBarFontOfSize:");
  Method originalMenuBarFontMethod = class_getClassMethod(fontClass, menuBarFontSelector);
  Method swizzledMenuBarFontMethod = class_getClassMethod(fontClass, @selector(eau_menuBarFontOfSize:));
  
  if (originalMenuBarFontMethod && swizzledMenuBarFontMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalMenuBarFontMethod);
    IMP swizzledIMP = method_getImplementation(swizzledMenuBarFontMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalMenuBarFontMethod, swizzledMenuBarFontMethod);
      NSDebugLog(@"NSFont+Eau: Successfully swizzled menuBarFontOfSize: method");
    } else {
      NSDebugLog(@"NSFont+Eau: menuBarFontOfSize: already swizzled, skipping");
    }
  } else {
    if (!originalMenuBarFontMethod) {
      NSLog(@"NSFont+Eau: ERROR - Could not find original menuBarFontOfSize: method");
    }
    if (!swizzledMenuBarFontMethod) {
      NSLog(@"NSFont+Eau: ERROR - Could not find eau_menuBarFontOfSize: method on NSFont");
    }
  }

  // Swizzle menuFontOfSize:
  SEL menuFontSelector = sel_registerName("menuFontOfSize:");
  Method originalMenuFontMethod = class_getClassMethod(fontClass, menuFontSelector);
  Method swizzledMenuFontMethod = class_getClassMethod(fontClass, @selector(eau_menuFontOfSize:));
  
  if (originalMenuFontMethod && swizzledMenuFontMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalMenuFontMethod);
    IMP swizzledIMP = method_getImplementation(swizzledMenuFontMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalMenuFontMethod, swizzledMenuFontMethod);
      NSDebugLog(@"NSFont+Eau: Successfully swizzled menuFontOfSize: method");
    } else {
      NSDebugLog(@"NSFont+Eau: menuFontOfSize: already swizzled, skipping");
    }
  } else {
    if (!originalMenuFontMethod) {
      NSLog(@"NSFont+Eau: ERROR - Could not find original menuFontOfSize: method");
    }
    if (!swizzledMenuFontMethod) {
      NSLog(@"NSFont+Eau: ERROR - Could not find eau_menuFontOfSize: method on NSFont");
    }
  }
}
