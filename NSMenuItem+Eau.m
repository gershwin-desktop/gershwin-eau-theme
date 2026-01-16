#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSMenuItem (Eau)

- (void) eau_awakeFromNib
{
  Method awakeMethod = class_getInstanceMethod([NSMenuItem class], @selector(awakeFromNib));
  Method eauMethod = class_getInstanceMethod([NSMenuItem class], @selector(eau_awakeFromNib));

  if (awakeMethod && eauMethod)
    {
      IMP awakeImp = method_getImplementation(awakeMethod);
      IMP eauImp = method_getImplementation(eauMethod);

      if (awakeImp != eauImp)
        {
          [self awakeFromNib];
        }
    }
}

    - (void) eau_applyHIGDefaults
    {
    }

    - (NSRect) frame
    {
      return NSZeroRect;
    }

    - (void) setFrame: (NSRect)frame
    {
    }

    - (NSSize) frameSize
    {
      return NSZeroSize;
    }

    - (void) setFrameSize: (NSSize)size
    {
    }

@end
