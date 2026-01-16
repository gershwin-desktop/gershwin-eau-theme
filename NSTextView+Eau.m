#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSTextView (Eau)

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSTextView class], @selector(initWithFrame:));
  Method eauInit = class_getInstanceMethod([NSTextView class], @selector(eau_initWithFrame:));

  if (originalInit && eauInit)
    {
      method_exchangeImplementations(originalInit, eauInit);
    }
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [self eau_initWithFrame: frameRect];

  if (self)
    {
      // Use standard text insets that follow 4px spacing rule
      [self setTextContainerInset: NSMakeSize(METRICS_SPACE_8 / 2.0, METRICS_SPACE_8 / 2.0)];
    }

  return self;
}

@end
