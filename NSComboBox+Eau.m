#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

@implementation NSComboBox (Eau)

static BOOL EAUComboBoxAwakeSwizzled = NO;
static BOOL EAUComboBoxAwakeInProgress = NO;
static IMP EAUComboBoxOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalAwake = class_getInstanceMethod([NSComboBox class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSComboBox class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUComboBoxOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUComboBoxAwakeSwizzled = YES;
    }
}

- (void) eau_awakeFromNib
{
  if (EAUComboBoxAwakeInProgress)
    {
      return;
    }

  EAUComboBoxAwakeInProgress = YES;

  if (EAUComboBoxAwakeSwizzled && EAUComboBoxOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUComboBoxOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }
  [self eau_applyHIGDefaults];

  EAUComboBoxAwakeInProgress = NO;
}

- (void) eau_applyHIGDefaults
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

@end
