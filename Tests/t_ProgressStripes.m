/* t_ProgressStripes.m - ObjectTesting coverage for the stripes of an
 * indeterminate progress bar under the Eau theme.
 *
 * The rules proven here (behavioral spec, gershwin-eau-theme):
 *
 *  1. A stripe offset of one pixel moves the stripes by one pixel, so a bar
 *     redrawn at a steady frame rate glides instead of jumping between a
 *     few fixed images.
 *  2. The stripes repeat every 48 px, the width of the stripe image, so the
 *     animation loops without a seam.
 *
 * Run with the theme under test, on a scratch display:
 *   DISPLAY=:97 ./obj/t_ProgressStripes -GSTheme $PWD/../Eau.theme
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import "Testing.h"

@interface GSTheme (EauProgressStripes)
- (void) drawProgressIndicator: (NSProgressIndicator*)progress
                    withBounds: (NSRect)bounds
                      withClip: (NSRect)rect
                       atCount: (int)count
                  stripeOffset: (CGFloat)stripeOffset
                      forValue: (double)val;
@end

/* Draws the theme's bar straight from drawRect: so the test sees exactly
 * what the hosted progress view paints for a given offset. */
@interface StripeView : NSView
{
@public
  NSProgressIndicator *indicator;
  CGFloat offset;
}
@end

@implementation StripeView
- (void) drawRect: (NSRect)rect
{
  [[GSTheme theme] drawProgressIndicator: indicator
                              withBounds: [self bounds]
                                withClip: [self bounds]
                                 atCount: 0
                            stripeOffset: offset
                                forValue: 0.0];
}
@end

/* Longer than a tagged small string: a file whose string literals all fit
 * into tagged pointers emits no constant string section, and the runtime's
 * section bounds then fail to link. */
static NSString * const kWindowTitle = @"Indeterminate progress stripes";

static const NSInteger kWidth = 200;
static const NSInteger kHeight = 20;

/* Middle row of the bar as gray levels; the stripes are diagonal, so one
 * row is enough to see where they are. */
static NSArray *stripeRow(StripeView *view, CGFloat offset)
{
  NSBitmapImageRep *rep;
  NSMutableArray *row = [NSMutableArray array];
  NSInteger x;

  view->offset = offset;
  /* GNUstep's cacheDisplayInRect: copies the window's backing store and
   * does not draw, so draw first. */
  [view display];
  rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
  [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
  for (x = 0; x < kWidth; x++)
    {
      NSColor *c = [[rep colorAtX: x y: kHeight / 2]
        colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
      [row addObject: [NSNumber numberWithInt:
        (int)lround([c whiteComponent] * 255.0)]];
    }
  return row;
}

/* Largest gray difference between row a and row b moved right by shift
 * pixels, ignoring the bezel at both ends. */
static int rowDistance(NSArray *a, NSArray *b, NSInteger shift)
{
  int worst = 0;
  NSInteger x;

  for (x = 10; x < kWidth - 10; x++)
    {
      int d = abs([[a objectAtIndex: x] intValue]
        - [[b objectAtIndex: x + shift] intValue]);
      if (d > worst)
        worst = d;
    }
  return worst;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSWindow *window;
  StripeView *view;
  NSProgressIndicator *indicator;
  NSArray *row0, *row1, *row48;

  [NSApplication sharedApplication];

  START_SET("indeterminate stripes")
  PASS([[GSTheme theme] respondsToSelector:
    @selector(drawProgressIndicator:withBounds:withClip:atCount:stripeOffset:forValue:)],
    "the theme draws stripes at a continuous offset");

  window = [[NSWindow alloc]
    initWithContentRect: NSMakeRect(100, 100, kWidth, kHeight)
              styleMask: NSBorderlessWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  view = [[StripeView alloc]
    initWithFrame: NSMakeRect(0, 0, kWidth, kHeight)];
  indicator = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(0, 0, kWidth, kHeight)];
  [indicator setStyle: NSProgressIndicatorBarStyle];
  [indicator setIndeterminate: YES];
  view->indicator = indicator;
  [window setTitle: kWindowTitle];
  [[window contentView] addSubview: view];
  [window orderFront: nil];

  row0 = stripeRow(view, 0.0);
  row1 = stripeRow(view, 1.0);
  row48 = stripeRow(view, 48.0);

  PASS(rowDistance(row0, row1, 0) > 16,
    "one pixel of offset changes the picture");
  /* The stripes travel left as the offset grows. */
  PASS(rowDistance(row1, row0, 1) <= 2,
    "one pixel of offset moves the stripes by exactly one pixel");
  PASS(rowDistance(row0, row48, 0) <= 2,
    "the stripes repeat after one 48 px image");
  END_SET("indeterminate stripes")

  [arp release];
  return 0;
}
