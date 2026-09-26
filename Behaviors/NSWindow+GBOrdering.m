/* NSWindow+GBOrdering.m - window presentation hooks and dialog diagnostics
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "GBTheme.h"
#import "GBThemeHooks+Window.h"

static BOOL GBIsDialogWindow(NSWindow *window)
{
  if (window == nil)
    {
      return NO;
    }
  if ([window isKindOfClass: [NSPanel class]])
    {
      return YES;
    }
  if ([window level] >= NSModalPanelWindowLevel)
    {
      return YES;
    }
  if (([window styleMask] & NSUtilityWindowMask) != 0)
    {
      return YES;
    }
  return NO;
}

static void GBCollectDialogTextFromView(NSMutableArray *parts, NSView *view)
{
  if (view == nil || parts == nil)
    {
      return;
    }

  /* Runs on windows that may be half torn down (close, orderOut:); a
   * diagnostic must never take the application with it. */
  @try {
    if ([view isKindOfClass: [NSTextField class]])
      {
        NSString *value = [(NSTextField *)view stringValue];
        if (value != nil && [value length] > 0)
          {
            [parts addObject: value];
          }
      }

    NSArray *subviews = nil;
    @try {
      subviews = [view subviews];
    } @catch (id ex) {}

    NSUInteger count = [subviews count];
    for (NSUInteger i = 0; i < count; i++)
      {
        @try {
          GBCollectDialogTextFromView(parts, [subviews objectAtIndex: i]);
        } @catch (id ex) {}
      }
  } @catch (NSException *e) {
  }
}

static NSString *GBDialogTextSummary(NSWindow *window)
{
  NSMutableArray *parts = [NSMutableArray array];
  NSString *title = [window title];
  if (title != nil && [title length] > 0)
    {
      [parts addObject: title];
    }
  GBCollectDialogTextFromView(parts, [window contentView]);
  if ([parts count] == 0)
    {
      return @"";
    }
  return [parts componentsJoinedByString: @" | "];
}

static void GBWindowLog(NSString *event, NSWindow *window)
{
  if (window == nil)
    {
      NSDebugLog(@"GBWindowLog: %@ window=(null)", event);
      return;
    }
  NSString *summary = nil;
  if (GBIsDialogWindow(window))
    {
      summary = GBDialogTextSummary(window);
    }
  NSDebugLog(@"GBWindowLog: %@ window=%p class=%@ title='%@' visible=%d key=%d main=%d level=%ld",
             event, window, NSStringFromClass([window class]), [window title],
             (int)[window isVisible], (int)[window isKeyWindow], (int)[window isMainWindow],
             (long)[window level]);
  if (summary != nil && [summary length] > 0)
    {
      NSDebugLog(@"GBDialog: window=%p class=%@ text='%@'", window,
                 NSStringFromClass([window class]), summary);
    }
}

static void GBWindowWillOrderFront(NSWindow *window)
{
  [GBThemeIfResponds(@selector(gbWindowWillOrderFront:)) gbWindowWillOrderFront: window];
}

@interface NSWindow (GBOrdering)
- (void) gb_orderFront: (id)sender;
- (void) gb_orderFrontRegardless;
- (void) gb_makeKeyAndOrderFront: (id)sender;
- (void) gb_orderOut: (id)sender;
- (void) gb_close;
@end

@implementation NSWindow (GBOrdering)

+ (void) load
{
  Class cls = [NSWindow class];
  Method orig;
  Method swiz;

  orig = class_getInstanceMethod(cls, @selector(orderFront:));
  swiz = class_getInstanceMethod(cls, @selector(gb_orderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderFrontRegardless));
  swiz = class_getInstanceMethod(cls, @selector(gb_orderFrontRegardless));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(makeKeyAndOrderFront:));
  swiz = class_getInstanceMethod(cls, @selector(gb_makeKeyAndOrderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderOut:));
  swiz = class_getInstanceMethod(cls, @selector(gb_orderOut:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(close));
  swiz = class_getInstanceMethod(cls, @selector(gb_close));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  /* Do not swizzle windowWillReturnFieldEditor:toObject: into NSWindow: it is
   * a delegate method, and the wrong type encoding crashed field editor
   * lookups (see NSWindow+GBDefaultButton.m). */

  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(gb_windowWillClose:)
                                               name: NSWindowWillCloseNotification
                                             object: nil];
}

+ (void) gb_windowWillClose: (NSNotification *)note
{
  GBWindowLog(@"willClose", (NSWindow *)[note object]);
}

- (void) gb_orderFront: (id)sender
{
  GBWindowLog(@"orderFront", self);
  GBWindowWillOrderFront(self);
  [self gb_orderFront: sender];
}

- (void) gb_orderFrontRegardless
{
  GBWindowLog(@"orderFrontRegardless", self);
  GBWindowWillOrderFront(self);
  [self gb_orderFrontRegardless];
}

- (void) gb_makeKeyAndOrderFront: (id)sender
{
  GBWindowLog(@"makeKeyAndOrderFront", self);
  GBWindowWillOrderFront(self);
  [self gb_makeKeyAndOrderFront: sender];
}

- (void) gb_orderOut: (id)sender
{
  GBWindowLog(@"orderOut", self);
  [self gb_orderOut: sender];
}

- (void) gb_close
{
  GBWindowLog(@"close", self);
  [self gb_close];
}

@end
