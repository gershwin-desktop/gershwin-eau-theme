#import "GSInfoPanel+Rik.h"
#import "Rik.h"
#import <AppKit/NSView.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSColor.h>
#import <objc/runtime.h>

@implementation GSInfoPanel (Rik)

+ (void)load
{
  static BOOL swizzled = NO;
  if (!swizzled)
    {
      swizzled = YES;
      
      Class class = [self class];
      
      SEL originalSelector = @selector(initWithDictionary:);
      SEL swizzledSelector = @selector(rik_initWithDictionary:);
      
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
      
      RIKLOG(@"GSInfoPanel+Rik: Swizzled initWithDictionary:");
    }
}

- (id)rik_initWithDictionary:(NSDictionary *)dictionary
{
  // Call the original implementation
  self = [self rik_initWithDictionary:dictionary];
  
  if (self) {
    RIKLOG(@"GSInfoPanel+Rik: Removing background image from info panel");
    
    // Set plain background color
    [self setBackgroundColor:[NSColor windowBackgroundColor]];
    
    // Remove the background image view
    NSView *contentView = [self contentView];
    NSArray *subviews = [[contentView subviews] copy];
    
    for (NSView *subview in subviews) {
      if ([subview isKindOfClass:[NSImageView class]]) {
        NSImageView *imageView = (NSImageView *)subview;
        NSRect frame = [imageView frame];
        NSRect contentFrame = [contentView frame];
        
        // Check if this is the background image (full size image view)
        if (NSEqualRects(frame, NSMakeRect(0, 0, contentFrame.size.width, contentFrame.size.height))) {
          RIKLOG(@"GSInfoPanel+Rik: Found and removing background image view");
          [imageView removeFromSuperview];
          break;
        }
      }
    }
    
    [subviews release];
  }
  
  return self;
}

@end
