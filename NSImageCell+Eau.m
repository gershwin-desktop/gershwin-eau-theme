#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSImageCell (Eau)

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSImageCell class], @selector(initImageCell:));
  Method swizzledInit = class_getInstanceMethod([NSImageCell class], @selector(eau_initImageCell:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }
}

- (id) eau_initImageCell: (NSImage *)image
{
  self = [self eau_initImageCell: image];
  if (self)
    {
      [self setImageAlignment: NSImageAlignCenter];
      [self setImageScaling: NSImageScaleProportionallyDown];
    }
  return self;
}

@end
