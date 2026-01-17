#import <AppKit/AppKit.h>
#import "EauGrowBoxCell.h"

@implementation EauGrowBoxCell

/**
 * Draw classic Mac-style grow box with diagonal ridges.
 * 3 diagonal lines from bottom-right toward top-left, each with highlight/shadow.
 */
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  if (NSIsEmptyRect(cellFrame))
    return;

  // Background - match scrollbar track color
  [[NSColor colorWithCalibratedWhite:0.85 alpha:1.0] set];
  NSRectFill(cellFrame);

  // Ridge colors
  NSColor *darkColor = [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
  NSColor *lightColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.8];

  CGFloat spacing = 3.0;  // Space between ridges
  CGFloat inset = 3.0;    // Offset from corner

  // Check if view is flipped to determine coordinate system
  BOOL flipped = [controlView isFlipped];

  // Draw 3 diagonal ridges in bottom-right corner
  for (int i = 0; i < 3; i++)
    {
      CGFloat offset = inset + (i * spacing);

      NSPoint darkStart, darkEnd, lightStart, lightEnd;

      if (flipped)
        {
          // Flipped: y increases downward, bottom is NSMaxY
          darkStart = NSMakePoint(NSMaxX(cellFrame), NSMaxY(cellFrame) - offset);
          darkEnd = NSMakePoint(NSMaxX(cellFrame) - offset, NSMaxY(cellFrame));
          lightStart = NSMakePoint(darkStart.x, darkStart.y - 1);
          lightEnd = NSMakePoint(darkEnd.x - 1, darkEnd.y);
        }
      else
        {
          // Non-flipped: y increases upward, bottom is NSMinY
          darkStart = NSMakePoint(NSMaxX(cellFrame), NSMinY(cellFrame) + offset);
          darkEnd = NSMakePoint(NSMaxX(cellFrame) - offset, NSMinY(cellFrame));
          lightStart = NSMakePoint(darkStart.x, darkStart.y + 1);
          lightEnd = NSMakePoint(darkEnd.x - 1, darkEnd.y);
        }

      // Dark line (shadow)
      NSBezierPath *darkLine = [NSBezierPath bezierPath];
      [darkLine moveToPoint:darkStart];
      [darkLine lineToPoint:darkEnd];
      [darkLine setLineWidth:1.0];
      [darkColor set];
      [darkLine stroke];

      // Light line (highlight)
      NSBezierPath *lightLine = [NSBezierPath bezierPath];
      [lightLine moveToPoint:lightStart];
      [lightLine lineToPoint:lightEnd];
      [lightLine setLineWidth:1.0];
      [lightColor set];
      [lightLine stroke];
    }
}

@end
