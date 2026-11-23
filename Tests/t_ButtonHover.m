/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_ButtonHover.m - a push button gives feedback while the pointer is over
 * it: its bezel color gets slightly brighter, never darker, and never by so
 * much that it reads as another state.
 */
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "EauButtonHover.h"

static double brightness(NSColor *c)
{
  return [[c colorUsingColorSpaceName: NSCalibratedRGBColorSpace]
    brightnessComponent];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSColor *gray = [NSColor colorWithCalibratedWhite: 0.85 alpha: 1];
  NSColor *blue = [NSColor colorWithCalibratedRed: 0.62 green: 0.82
                                             blue: 0.965 alpha: 1];
  NSColor *white = [NSColor whiteColor];
  NSColor *hg = EauHoverColor(gray);
  NSColor *hb = EauHoverColor(blue);
  NSColor *rgbIn = [blue colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  NSColor *rgbOut = [hb colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

  PASS(brightness(hg) > brightness(gray) + 0.02, "gray gets brighter");
  PASS(brightness(hg) < brightness(gray) + 0.15, "gray gets only slightly brighter");
  PASS(brightness(hb) > brightness(blue), "blue gets brighter");
  PASS(fabs([rgbOut hueComponent] - [rgbIn hueComponent]) < 0.02,
       "hue is kept");
  PASS(brightness(EauHoverColor(white)) <= 1.0, "white stays in range");
  PASS(EauHoverColor(nil) == nil,
       "nil stays nil");
  [arp release];
  return 0;
}
