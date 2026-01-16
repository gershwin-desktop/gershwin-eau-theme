#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (EauTableExtensions)
- (CGFloat) tableHeaderRowHeight;
@end

@implementation NSTableHeaderView (Eau)

static BOOL EAUHeaderViewAwakeSwizzled = NO;
static BOOL EAUHeaderViewAwakeInProgress = NO;
static IMP EAUHeaderViewOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalAwake = class_getInstanceMethod([NSTableHeaderView class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSTableHeaderView class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUHeaderViewOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUHeaderViewAwakeSwizzled = YES;
    }
}

- (void) eau_awakeFromNib
{
  if (EAUHeaderViewAwakeInProgress)
    {
      return;
    }

  EAUHeaderViewAwakeInProgress = YES;

  if (EAUHeaderViewAwakeSwizzled && EAUHeaderViewOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUHeaderViewOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }

  CGFloat headerHeight = [[GSTheme theme] tableHeaderRowHeight];
  NSSize headerSize = [self frame].size;
  if (headerHeight > 0 && headerSize.height != headerHeight)
    {
      headerSize.height = headerHeight;
      [self setFrameSize: headerSize];
    }

  EAUHeaderViewAwakeInProgress = NO;
}

@end
