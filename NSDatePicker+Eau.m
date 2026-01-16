#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation NSDatePicker (Eau)

+ (void) load
{
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [self eau_initWithFrame: frameRect];
  if (self)
    {
      if ([self respondsToSelector:@selector(setFont:)])
        {
          [self setFont: METRICS_FONT_SYSTEM_REGULAR_13];
        }

      if ([self respondsToSelector:@selector(setControlSize:)])
        {
          ((void (*)(id, SEL, NSControlSize))objc_msgSend)(self, @selector(setControlSize:), NSRegularControlSize);
        }
    }

  return self;
}

@end
