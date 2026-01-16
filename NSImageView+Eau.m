#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSImageView (Eau)

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSImageView class], @selector(initWithFrame:));
  Method swizzledInit = class_getInstanceMethod([NSImageView class], @selector(eau_initWithFrame:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [self eau_initWithFrame: frameRect];
  if (self)
    {
      if ([self respondsToSelector:@selector(setImageScaling:)])
        {
          [self setImageScaling: NSImageScaleProportionallyDown];
        }
    }

  return self;
}

@end
