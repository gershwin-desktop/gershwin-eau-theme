#include "Eau.h"

// @interface NSSegmentedCell(EauTheme)
@interface Eau(NSSegmentedCell)
@end
@interface Eau(NSSegmentedCellDrawing)
@end
@implementation Eau(NSSegmentedCell)


// - (NSColor*) textColor
- (NSColor*) _overrideNSSegmentedCellMethod_textColor
{
  NSDebugLog(@"_overrideNSSegmentedCellMethod_textColor");
  //IT DOES NOT WORKS
  NSSegmentedCell *xself = (NSSegmentedCell*) self;
  
  if([xself state] == GSThemeSelectedState)
    return [NSColor whiteColor];
  if ([xself isEnabled] == NO)
    return [NSColor disabledControlTextColor];
  else
    return [NSColor controlTextColor];
}
// - (void) _drawBorderAndBackgroundWithFrame: (NSRect)cellFrame
//                                     inView: (NSView*)controlView
- (void) _overrideNSSegmentedCellMethod__drawBorderAndBackgroundWithFrame: (NSRect)cellFrame
                                    inView: (NSView*)controlView
{
  NSDebugLog(@"_overrideNSSegmentedCellMethod__drawBorderAndBackgroundWithFrame");
  NSSegmentedCell *xself = (NSSegmentedCell*) self;
  CGFloat radius = 4;
  cellFrame = NSInsetRect(cellFrame, 0.5, 0.5);
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSBezierPath* roundedRectanglePath = [NSBezierPath bezierPathWithRoundedRect: cellFrame
                                                                       xRadius: radius
                                                                       yRadius: radius];
  [strokeColorButton setStroke];
  [roundedRectanglePath setLineWidth: 1];
  [roundedRectanglePath stroke];
  NSInteger i;
  NSUInteger count = [xself segmentCount];
  NSRect frame = cellFrame;
  NSRect controlFrame = [controlView frame];

  NSBezierPath* linesPath = [NSBezierPath bezierPath];
  [linesPath setLineWidth: 1];
  CGFloat offsetX = 0;
  for (i = 0; i < (NSInteger)count - 1; i++)
    {
      frame.size.width = [xself widthForSegment: i];
      if(frame.size.width == 0.0)
        {
          frame.size.width = (controlFrame.size.width - frame.origin.x) / (count);
        }
      offsetX += frame.size.width;
      offsetX = floor(offsetX) + 0.5;
      [linesPath moveToPoint: NSMakePoint(offsetX, NSMinY(frame) + 3)];
      [linesPath lineToPoint: NSMakePoint(offsetX, NSMaxY(frame) - 3)];
    }
  [linesPath stroke];
}
@end

/* libs-gui draws every segment as enabled, so a disabled one (Back with
 * nothing to go back to) looked exactly like an enabled one.  Redraw those
 * segments with a plain bezel and a faded image.  The frames follow
 * -[NSSegmentedCell drawInteriorWithFrame:inView:].
 * TODO: Upstream to GNUstep - -drawSegment:inFrame:withView: should honour
 * -isEnabledForSegment: and -isEnabled. */
static void EauDimDisabledSegments(NSSegmentedCell *xself, NSRect cellFrame,
                                   NSView *controlView)
{
  NSInteger count = [xself segmentCount];
  NSRect frame = cellFrame;
  NSRect controlFrame = [controlView frame];
  BOOL controlEnabled = [xself isEnabled];
  NSInteger i;

  for (i = 0; i < count; i++)
    {
      frame.size.width = [xself widthForSegment: i];
      if (frame.size.width == 0.0)
        {
          frame.size.width = (controlFrame.size.width - frame.origin.x) / (count - i);
        }

      if (controlEnabled == NO || [xself isEnabledForSegment: i] == NO)
        {
          NSImage *image = [xself imageForSegment: i];

          [[GSTheme theme] drawSegmentedControlSegment: xself
                                             withFrame: frame
                                                inView: controlView
                                                 style: [xself segmentStyle]
                                                 state: GSThemeDisabledState
                                           roundedLeft: (i == 0)
                                          roundedRight: (i == count - 1)];
          if (image != nil)
            {
              NSSize size = [image size];
              NSRect dest = NSMakeRect(MAX(NSMidX(frame) - size.width / 2., 0.),
                                       MAX(NSMidY(frame) - size.height / 2., 0.),
                                       size.width, size.height);

              [image drawInRect: [controlView centerScanRect: dest]
                       fromRect: NSZeroRect
                      operation: NSCompositeSourceOver
                       fraction: 0.35];
            }
        }

      frame.origin.x += frame.size.width;
      if (frame.origin.x >= cellFrame.size.width)
        break;
    }
}

@implementation Eau(NSSegmentedCellDrawing)

// - (void) drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
- (void) _overrideNSSegmentedCellMethod_drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  NSDebugLog(@"_overrideNSSegmentedCellMethod_drawWithFrame");
  NSCell *xself = (NSCell*) self;
  if (NSIsEmptyRect(cellFrame))
    return;
// i want to draw the border for last
  [xself drawInteriorWithFrame: cellFrame inView: controlView];
  EauDimDisabledSegments((NSSegmentedCell *) self, cellFrame, controlView);
  [xself _drawBorderAndBackgroundWithFrame: cellFrame inView: controlView];
  [xself _drawFocusRingWithFrame: cellFrame inView: controlView];
}
@end
