#import "Eau.h"

@interface GSTheme()

- (void) drawCircularBezel: (NSRect)cellFrame
                 withColor: (NSColor*)backgroundColor;
@end

@interface Eau (EauSliderPrivate)
- (NSColor *) fadedForDisabled: (NSColor *)color;
@end

@implementation Eau (EauSlider)
- (void) drawSliderBorderAndBackground: (NSBorderType)aType
				 frame: (NSRect)cellFrame
				inCell: (NSCell *)cell
			  isHorizontal: (BOOL)horizontal
{
}

- (void) drawBarInside: (NSRect)rect
		inCell: (NSCell *)cell
	       flipped: (BOOL)flipped
{
  NSSliderType type = [(NSSliderCell *)cell sliderType];
  if (type == NSLinearSlider)
    {
      BOOL horizontal = (rect.size.width > rect.size.height);

      //// Color Declarations
      NSColor* strokeBaseColor = [NSColor colorWithCalibratedRed: 0.733 green: 0.733 blue: 0.733 alpha: 1];
      NSColor* strokeLight = [strokeBaseColor shadowWithLevel: 0.2];
      NSColor* strokeDark = [strokeBaseColor shadowWithLevel: 0.5];
      NSColor* strokeDark2 = [strokeBaseColor shadowWithLevel: 0.4];
      NSColor* strokeLight2 = [strokeBaseColor highlightWithLevel: 0.1];
      /* A disabled slider was drawn exactly like an enabled one, so a
       * setting that could not be changed looked as if it could. */
      if (![cell isEnabled])
        {
          strokeLight = [self fadedForDisabled: strokeLight];
          strokeDark = [self fadedForDisabled: strokeDark];
          strokeDark2 = [self fadedForDisabled: strokeDark2];
          strokeLight2 = [self fadedForDisabled: strokeLight2];
        }

      //// Gradient Declarations
      NSGradient* strokeGradient = [[NSGradient alloc] initWithStartingColor: strokeDark endingColor: strokeLight];
      NSGradient* fillGradient = [[NSGradient alloc] initWithColorsAndLocations:
          strokeDark2, 0.0,
          strokeLight2, 1.0, nil];
      int w,h,a,x,y;
      if(horizontal)
      {
        w = NSWidth(rect) - 4;
        h = 6;
        a = 90;
        x = NSMinX(rect) + 2;
        y = NSMinY(rect) + NSHeight(rect)/2 - h/2;
      }
      else
      {
        w = 6;
        h = NSHeight(rect) - 4;
        a = 0;
        x = NSMinX(rect) + NSWidth(rect)/2 - floor(w * 0.5 - 0.5) ;
        y = NSMinY(rect);
      }
      rect.size.height = 8;
      NSRect r = NSMakeRect(x, y, w, h);
      NSRect r2 = NSMakeRect(x+1, y+1, w-2, h-2 );
      //// border Drawing
      NSBezierPath* borderPath = [NSBezierPath bezierPathWithRoundedRect:r  xRadius: 3 yRadius: 3];
      [strokeGradient drawInBezierPath: borderPath angle: a];


      //// fill Drawing
      NSBezierPath* fillPath = [NSBezierPath bezierPathWithRoundedRect:r2  xRadius: 3 yRadius: 3];
      [fillGradient drawInBezierPath: fillPath angle: a];
    }
}

- (void) drawKnobInCell: (NSCell *)cell
{
  NSView *controlView = [cell controlView];
  NSSliderCell *sliderCell = (NSSliderCell *)cell;
  NSRect r = 	[sliderCell knobRectFlipped: [controlView isFlipped]];
  r.size.height += 2;
  r.size.width += 2;
  r.origin.x -= 1;
  r.origin.y -= 1;
  NSColor	*color = [NSColor colorWithCalibratedRed: 0.9
                                             green: 0.9
                                              blue: 0.9
                                             alpha: 1];
  if (![cell isEnabled])
    {
      /* The bezel strokes every knob in the full control stroke colour;
       * a disabled knob is drawn faded as a whole instead. */
      CGFloat radius = MIN(NSWidth(r), NSHeight(r)) / 2;
      NSRect circle = NSMakeRect(NSMidX(r) - radius, NSMinY(r),
                                 radius * 2, radius * 2);
      NSBezierPath *knob =
        [NSBezierPath bezierPathWithOvalInRect: NSInsetRect(circle, 0.5, 0.5)];
      [[self fadedForDisabled: color] setFill];
      [knob fill];
      [[self fadedForDisabled: [Eau controlStrokeColor]] setStroke];
      [knob stroke];
      return;
    }
  [self drawCircularBezel:r  withColor: color];
}

/* Halfway to the window's background: still there, clearly not usable. */
- (NSColor *) fadedForDisabled: (NSColor *)color
{
  return [color blendedColorWithFraction: 0.55
                                 ofColor: [NSColor windowBackgroundColor]];
}
@end
