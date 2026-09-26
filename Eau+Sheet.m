/* Eau+Sheet.m - Aqua look for window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Implements the optional hooks of Behaviors/GBThemeHooks+Sheet.h; the
 * behaviour itself lives in GershwinBehaviors.bundle.
 */

#import <AppKit/AppKit.h>

#import "Behaviors/GBThemeHooks+Sheet.h"
#import "Eau.h"

/* Aqua sheets glide out in about a fifth of a second: long enough to show
 * where the sheet comes from, short enough not to slow the user down. */
static const NSTimeInterval kEauSheetSlideDuration = 0.2;

/* Depth of the shadow the parent's titlebar casts onto the sheet top. */
static const CGFloat kEauSheetTopShadowHeight = 6.0;

@implementation Eau (Sheet)

- (NSTimeInterval)sheetAnimationDurationForWindow:(NSWindow *)sheet
{
  return kEauSheetSlideDuration;
}

- (void)drawSheetBorderInRect:(NSRect)bounds forWindow:(NSWindow *)sheet
{
  NSRect shadow;
  NSGradient *gradient;
  NSBezierPath *edge = [NSBezierPath bezierPath];

  /* The sheet looks tucked under the titlebar: darkest right at the top
   * edge, fading into the sheet background. */
  shadow = NSMakeRect(NSMinX(bounds), NSMaxY(bounds) - kEauSheetTopShadowHeight, NSWidth(bounds),
                      kEauSheetTopShadowHeight);
  gradient =
      [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.0]
                                    endingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.22]];
  [gradient drawInRect:shadow angle:90];

  /* No line along the top: that edge meets the titlebar. */
  [edge moveToPoint:NSMakePoint(NSMinX(bounds) + 0.5, NSMaxY(bounds))];
  [edge lineToPoint:NSMakePoint(NSMinX(bounds) + 0.5, NSMinY(bounds) + 0.5)];
  [edge lineToPoint:NSMakePoint(NSMaxX(bounds) - 0.5, NSMinY(bounds) + 0.5)];
  [edge lineToPoint:NSMakePoint(NSMaxX(bounds) - 0.5, NSMaxY(bounds))];
  [edge setLineWidth:1.0];
  [[NSColor colorWithCalibratedWhite:0.45 alpha:1.0] set];
  [edge stroke];
}

@end
