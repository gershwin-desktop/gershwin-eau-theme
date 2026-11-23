/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauButtonHover.h"
#import <objc/runtime.h>

/* Small enough to read as a hint, not as the highlighted state. */
static const CGFloat kHoverWhiteFraction = 0.4;

static char kTrackerKey;

@interface EauHoverTracker : NSObject
{
  NSTrackingRectTag _tag;
  BOOL _hasTag;
}
@property (nonatomic, weak) NSView *view;
- (void)install;
@end

@implementation EauHoverTracker
- (void)install
{
  NSView *view = self.view;

  if (_hasTag)
    [view removeTrackingRect:_tag];
  _tag = [view addTrackingRect:[view bounds] owner:self userData:NULL
                  assumeInside:NO];
  _hasTag = YES;
}
- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  if (_hasTag)
    [self.view removeTrackingRect:_tag];
}
- (void)mouseEntered:(NSEvent *)event
{
  [self.view setNeedsDisplay:YES];
}
- (void)mouseExited:(NSEvent *)event
{
  [self.view setNeedsDisplay:YES];
}
@end

NSColor *EauHoverColor(NSColor *color)
{
  NSColor *rgb;
  CGFloat h, s, b, a;

  if (color == nil)
    return nil;
  rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if (rgb == nil)
    return color;
  /* Blending towards white would wash a saturated blue out; raising only
   * brightness keeps the hue and the character of the color. */
  [rgb getHue:&h saturation:&s brightness:&b alpha:&a];
  b = b + (1.0 - b) * kHoverWhiteFraction;
  if (s > 0.0 && b >= 1.0)
    s = MAX(0.0, s - 0.05);
  return [NSColor colorWithCalibratedHue:h saturation:s brightness:MIN(b, 1.0)
                                   alpha:a];
}

BOOL EauPointerIsInside(NSView *view, NSRect frame)
{
  NSWindow *window = [view window];

  if (window == nil || ![window isVisible])
    return NO;
  return [view mouse:[view convertPoint:[window mouseLocationOutsideOfEventStream]
                               fromView:nil]
              inRect:frame];
}

void EauTrackPointerForView(NSView *view)
{
  EauHoverTracker *tracker;

  if (view == nil || objc_getAssociatedObject(view, &kTrackerKey) != nil)
    return;
  tracker = [EauHoverTracker new];
  tracker.view = view;
  /* The rectangle is in view coordinates and does not follow a resize, so
   * it is made again whenever the view changes size. */
  [view setPostsFrameChangedNotifications:YES];
  [view setPostsBoundsChangedNotifications:YES];
  [[NSNotificationCenter defaultCenter] addObserver:tracker
    selector:@selector(install) name:NSViewFrameDidChangeNotification object:view];
  [[NSNotificationCenter defaultCenter] addObserver:tracker
    selector:@selector(install) name:NSViewBoundsDidChangeNotification object:view];
  [tracker install];
  objc_setAssociatedObject(view, &kTrackerKey, tracker,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
