#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSClipView (Eau)

static BOOL EAUClipViewAwakeSwizzled = NO;
static BOOL EAUClipViewAwakeInProgress = NO;
static IMP EAUClipViewOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSClipView class], @selector(initWithFrame:));
  Method swizzledInit = class_getInstanceMethod([NSClipView class], @selector(eau_initWithFrame:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }

  Method originalAwake = class_getInstanceMethod([NSClipView class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSClipView class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUClipViewOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUClipViewAwakeSwizzled = YES;
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
  if (EAUClipViewAwakeInProgress)
    {
      return;
    }

  EAUClipViewAwakeInProgress = YES;

  if (EAUClipViewAwakeSwizzled && EAUClipViewOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUClipViewOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }
  [self eau_applyHIGDefaults];

  EAUClipViewAwakeInProgress = NO;
}

- (void) eau_applyHIGDefaults
{
  [self setDrawsBackground: YES];
  [self setBackgroundColor: [NSColor windowBackgroundColor]];
}

@end
