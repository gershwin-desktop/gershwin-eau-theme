#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSMatrix (Eau)

static BOOL EAUMatrixAwakeSwizzled = NO;
static BOOL EAUMatrixAwakeInProgress = NO;
static IMP EAUMatrixOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSMatrix class], @selector(initWithFrame:));
  Method swizzledInit = class_getInstanceMethod([NSMatrix class], @selector(eau_initWithFrame:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }

  Method originalAwake = class_getInstanceMethod([NSMatrix class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSMatrix class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUMatrixOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUMatrixAwakeSwizzled = YES;
    }
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  self = [self eau_initWithFrame: frameRect];
  if (self)
    {
      [self eau_applyHIGDefaults];
    }
  return self;
}

- (void) eau_awakeFromNib
{
  if (EAUMatrixAwakeInProgress)
    {
      return;
    }

  EAUMatrixAwakeInProgress = YES;

  if (EAUMatrixAwakeSwizzled && EAUMatrixOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUMatrixOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }
  [self eau_applyHIGDefaults];

  EAUMatrixAwakeInProgress = NO;
}

- (void) eau_applyHIGDefaults
{
  // Align stacked radio/checkbox rows with HIG spacing guidance
  if ([self respondsToSelector:@selector(setIntercellSpacing:)])
    {
      NSSize spacing = [self intercellSpacing];
      spacing.height = METRICS_CHECKBOX_STACK_SPACING;
      [self setIntercellSpacing: spacing];
    }
}

@end
