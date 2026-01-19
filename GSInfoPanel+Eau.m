#import "GSInfoPanel+Eau.h"
#import "Eau.h"
#import <AppKit/NSView.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSColor.h>
#import <objc/runtime.h>

@implementation GSInfoPanel (Eau)

+ (void)load
{
  static BOOL swizzled = NO;
  if (!swizzled)
    {
      swizzled = YES;
      
      Class class = [self class];
      
      SEL originalSelector = @selector(initWithDictionary:);
      SEL swizzledSelector = @selector(eau_initWithDictionary:);
      
      Method originalMethod = class_getInstanceMethod(class, originalSelector);
      Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
      
      BOOL didAddMethod = class_addMethod(class,
                                          originalSelector,
                                          method_getImplementation(swizzledMethod),
                                          method_getTypeEncoding(swizzledMethod));
      
      if (didAddMethod)
        {
          class_replaceMethod(class,
                              swizzledSelector,
                              method_getImplementation(originalMethod),
                              method_getTypeEncoding(originalMethod));
        }
      else
        {
          method_exchangeImplementations(originalMethod, swizzledMethod);
        }
      
      EAULOG(@"GSInfoPanel+Eau: Swizzled initWithDictionary:");
    }
}

- (id)eau_initWithDictionary:(NSDictionary *)dictionary __attribute__((objc_method_family(init)))
{
  // Call the original implementation
  id result = [self eau_initWithDictionary:dictionary];
  
  if (result) {
    EAULOG(@"GSInfoPanel+Eau: Removing background image from info panel");
    
    // Set plain background color
    [result setBackgroundColor:[NSColor windowBackgroundColor]];
    
    // Remove the background image view
    NSView *contentView = [result contentView];
    NSArray *subviews = [[contentView subviews] copy];
    
    for (NSView *subview in subviews) {
      if ([subview isKindOfClass:[NSImageView class]]) {
        NSImageView *imageView = (NSImageView *)subview;
        NSRect frame = [imageView frame];
        NSRect contentFrame = [contentView frame];
        
        // Check if this is the background image (full size image view)
        if (NSEqualRects(frame, NSMakeRect(0, 0, contentFrame.size.width, contentFrame.size.height))) {
          EAULOG(@"GSInfoPanel+Eau: Found and removing background image view");
          [imageView removeFromSuperview];
          break;
        }
      }
    }
    
  }
  
  return result;
}

@end
