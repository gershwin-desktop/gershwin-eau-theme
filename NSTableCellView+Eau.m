#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSTableCellView (Eau)

static BOOL EAUTableCellViewAwakeSwizzled = NO;
static BOOL EAUTableCellViewAwakeInProgress = NO;
static IMP EAUTableCellViewOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalAwake = class_getInstanceMethod([NSTableCellView class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSTableCellView class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUTableCellViewOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUTableCellViewAwakeSwizzled = YES;
    }
}

- (void) eau_awakeFromNib
{
  if (EAUTableCellViewAwakeInProgress)
    {
      return;
    }

  EAUTableCellViewAwakeInProgress = YES;

  if (EAUTableCellViewAwakeSwizzled && EAUTableCellViewOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUTableCellViewOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }

  if ([self respondsToSelector:@selector(textField)])
    {
      NSTextField *field = [self textField];
      if (field != nil)
        {
          [field setFont: METRICS_FONT_SYSTEM_REGULAR_13];
          [[field cell] setLineBreakMode: NSLineBreakByTruncatingTail];
        }
    }

  EAUTableCellViewAwakeInProgress = NO;
}

@end
