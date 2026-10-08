/* t_SliderDisabled.m - ObjectTesting coverage for disabled sliders under
 * the Eau theme.
 *
 * The rule proven here (behavioral spec, gershwin-eau-theme):
 *
 *  A disabled slider looks disabled: its track and knob are drawn fainter
 *  than an enabled slider's, so a setting that cannot be changed does not
 *  look as if it could. Eau drew both the same.
 *
 * Run with the theme under test, on a scratch display:
 *   DISPLAY=:97 ./obj/t_SliderDisabled -GSTheme $PWD/../Eau.theme
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import "Testing.h"

/* How much ink the view puts on the window background: the mean darkness
 * of its pixels, 0 for a blank view. */
static double ink(NSView *view)
{
  NSBitmapImageRep *rep;
  NSInteger x, y, w, h;
  double sum = 0.0;

  /* GNUstep's cacheDisplayInRect: copies the window's backing store and
   * does not draw, so draw first. */
  [view display];
  rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
  [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
  w = [rep pixelsWide];
  h = [rep pixelsHigh];
  for (y = 0; y < h; y++)
    for (x = 0; x < w; x++)
      {
        NSColor *c = [[rep colorAtX: x y: y]
          colorUsingColorSpaceName: NSCalibratedWhiteColorSpace];
        sum += 1.0 - [c whiteComponent];
      }
  return sum / (double)(w * h);
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSWindow *window;
  NSSlider *enabled, *disabled;
  double enabledInk, disabledInk;

  [NSApplication sharedApplication];
  PASS([[[GSTheme theme] name] isEqualToString: @"Eau"],
       "Eau theme is active (%s)", [[[GSTheme theme] name] UTF8String]);

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 260, 80)
                                       styleMask: NSTitledWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  /* Also keeps the tool linkable: with only strings short enough to be
   * tagged pointers ("Eau") the object has no constant string section, yet
   * refers to its bounds, and the link fails. */
  [window setTitle: @"Enabled and disabled sliders"];
  enabled = [[NSSlider alloc] initWithFrame: NSMakeRect(10, 45, 200, 22)];
  disabled = [[NSSlider alloc] initWithFrame: NSMakeRect(10, 10, 200, 22)];
  [enabled setDoubleValue: 0.6];
  [disabled setDoubleValue: 0.6];
  [disabled setEnabled: NO];
  [[window contentView] addSubview: enabled];
  [[window contentView] addSubview: disabled];
  [window orderFront: nil];

  enabledInk = ink(enabled);
  disabledInk = ink(disabled);
  PASS(enabledInk > 0.02, "an enabled slider is drawn (ink %.3f)", enabledInk);
  PASS(disabledInk < enabledInk * 0.75,
       "a disabled slider is drawn fainter (ink %.3f against %.3f)",
       disabledInk, enabledInk);
  PASS(disabledInk > 0.005,
       "but is still there to be seen (ink %.3f)", disabledInk);

  [window orderOut: nil];
  [enabled release];
  [disabled release];
  [window release];
  [arp release];
  return 0;
}
