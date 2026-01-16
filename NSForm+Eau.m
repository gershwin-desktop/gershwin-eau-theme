#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static CGFloat EauFormSpacingForControlSize(NSControlSize size)
{
  switch (size)
    {
      case NSSmallControlSize: return METRICS_TEXT_FIELD_VERTICAL_SPACING_SMALL;
      case NSMiniControlSize: return METRICS_TEXT_FIELD_VERTICAL_SPACING_MINI;
      default: return METRICS_TEXT_FIELD_VERTICAL_SPACING;
    }
}

@implementation NSForm (Eau)

static BOOL EAUFormAwakeSwizzled = NO;
static BOOL EAUFormAwakeInProgress = NO;
static IMP EAUFormOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSForm class], @selector(initWithFrame:));
  Method swizzledInit = class_getInstanceMethod([NSForm class], @selector(eau_initWithFrame:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }

  Method originalAwake = class_getInstanceMethod([NSForm class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSForm class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUFormOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUFormAwakeSwizzled = YES;
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
  if (EAUFormAwakeInProgress)
    {
      return;
    }

  EAUFormAwakeInProgress = YES;

  if (EAUFormAwakeSwizzled && EAUFormOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUFormOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }
  [self eau_applyHIGDefaults];

  EAUFormAwakeInProgress = NO;
}

- (void) eau_applyHIGDefaults
{
  NSControlSize size = NSRegularControlSize;
  if ([self respondsToSelector:@selector(controlSize)])
    {
      size = (NSControlSize)(NSInteger)objc_msgSend(self, @selector(controlSize));
    }

  if ([self respondsToSelector:@selector(setInterlineSpacing:)])
    {
      [self setInterlineSpacing: EauFormSpacingForControlSize(size)];
    }
}

@end
