#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void EauRemoveDialogSeparators(NSView *view)
{
  NSArray *subviews = [[view subviews] copy];
  for (NSView *subview in subviews)
    {
      if ([subview isKindOfClass:[NSBox class]])
        {
          NSBox *box = (NSBox *)subview;
          NSBorderType borderType = [box borderType];
          NSRect frame = [box frame];
          BOOL isSeparator = (borderType == NSGrooveBorder || borderType == NSLineBorder)
            && (frame.size.height <= 3.0 || frame.size.width <= 3.0);

          if (isSeparator)
            {
              [box removeFromSuperview];
              continue;
            }
        }

      EauRemoveDialogSeparators(subview);
    }
  [subviews release];
}

@interface NSPanel (EauTheme)
- (void) eau_applyDialogAppearance;
- (id) eau_initWithContentRect: (NSRect)contentRect
                     styleMask: (NSUInteger)styleMask
                       backing: (NSBackingStoreType)backingType
                         defer: (BOOL)flag;
- (void) eau_awakeFromNib;
@end

@implementation NSPanel (EauTheme)

static BOOL EAUPanelAwakeSwizzled = NO;
static BOOL EAUPanelAwakeInProgress = NO;
static IMP EAUPanelOriginalAwakeImp = NULL;

+ (void) load
{
  Method originalInit = class_getInstanceMethod([NSPanel class], @selector(initWithContentRect:styleMask:backing:defer:));
  Method swizzledInit = class_getInstanceMethod([NSPanel class], @selector(eau_initWithContentRect:styleMask:backing:defer:));
  if (originalInit && swizzledInit)
    {
      method_exchangeImplementations(originalInit, swizzledInit);
    }

  Method originalAwake = class_getInstanceMethod([NSPanel class], @selector(awakeFromNib));
  Method swizzledAwake = class_getInstanceMethod([NSPanel class], @selector(eau_awakeFromNib));
  if (originalAwake && swizzledAwake)
    {
      EAUPanelOriginalAwakeImp = method_getImplementation(originalAwake);
      method_exchangeImplementations(originalAwake, swizzledAwake);
      EAUPanelAwakeSwizzled = YES;
    }
}

- (id) eau_initWithContentRect: (NSRect)contentRect
                     styleMask: (NSUInteger)styleMask
                       backing: (NSBackingStoreType)backingType
                         defer: (BOOL)flag
{
  self = [self eau_initWithContentRect: contentRect
                             styleMask: styleMask
                               backing: backingType
                                 defer: flag];
  if (self)
    {
      [self eau_applyDialogAppearance];
    }
  return self;
}

- (void) eau_awakeFromNib
{
  if (EAUPanelAwakeInProgress)
    {
      return;
    }

  EAUPanelAwakeInProgress = YES;

  if (EAUPanelAwakeSwizzled && EAUPanelOriginalAwakeImp)
    {
      ((void (*)(id, SEL))EAUPanelOriginalAwakeImp)(self, @selector(awakeFromNib));
    }
  else
    {
      [super awakeFromNib];
    }
  [self eau_applyDialogAppearance];

  EAUPanelAwakeInProgress = NO;
}

- (void) eau_applyDialogAppearance
{
  if ([self respondsToSelector:@selector(setBackgroundColor:)])
    {
      [self setBackgroundColor: [NSColor windowBackgroundColor]];
    }

  NSView *contentView = [self contentView];
  if (contentView != nil)
    {
      EauRemoveDialogSeparators(contentView);
    }
}

@end
