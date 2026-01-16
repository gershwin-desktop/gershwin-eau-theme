#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation NSLevelIndicator (Eau)

+ (void) load
{
  // Disabled: in some GNUstep builds NSLevelIndicator aliases NSScroller,
  // and swizzling initWithFrame leads to recursion/crashes for all apps.
  return;
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [super initWithFrame: frameRect];
  if (self)
    {
      if ([self respondsToSelector:@selector(setControlSize:)])
        {
          ((void (*)(id, SEL, NSControlSize))objc_msgSend)(self, @selector(setControlSize:), NSRegularControlSize);
        }
    }

  return self;
}

@end
