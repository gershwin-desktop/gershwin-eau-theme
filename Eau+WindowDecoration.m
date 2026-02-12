#import "Eau.h"
#import "Eau+TitleBarButtons.h"
#import "AppearanceMetrics.h"

@interface Eau(EauWindowDecoration)

@end


#define TITLE_HEIGHT 24.0
#define RESIZE_HEIGHT 9.0

@implementation Eau(EauWindowDecoration)

static NSDictionary *titleTextAttributes[3] = {nil, nil, nil};


- (float) resizebarHeight {
    return 0.0;  // No resize bar
}

- (float) titlebarHeight {
    return TITLE_HEIGHT;
}

- (void) drawWindowBackground: (NSRect) frame view: (NSView*) view
{
  NSColor* backgroundColor = [[view window] backgroundColor];
  [backgroundColor setFill];
  NSRectFill(frame);
}

- (void) drawWindowBorder: (NSRect)rect
                withFrame: (NSRect)frame
             forStyleMask: (unsigned int)styleMask
                    state: (int)inputState
                 andTitle: (NSString*)title
{
  if (styleMask & (NSTitledWindowMask | NSClosableWindowMask
                  | NSMiniaturizableWindowMask))
    {
      NSRect titleRect;

      titleRect = NSMakeRect(0.0, frame.size.height - TITLE_HEIGHT,
                                frame.size.width, TITLE_HEIGHT);

      if (NSIntersectsRect(rect, titleRect))
        [self drawtitleRect: titleRect
              forStyleMask: styleMask
              state: inputState
              andTitle: title];

    }
}


- (void) drawtitleRect: (NSRect)titleRect
             forStyleMask: (unsigned int)styleMask
                    state: (int)inputState
                 andTitle: (NSString*)title
{

  if (!titleTextAttributes[0])
    {
      [self prepareTitleTextAttributes];
    }

  // Map GSThemeControlState to titleTextAttributes index (0=active, 1=inactive, 2=main)
  // GSThemeNormalState=0 → active, GSThemeSelectedState=6 → inactive, anything else → inactive
  int attrIndex = (inputState == 0) ? 0 : 1;

  NSRect workRect;
  CGFloat titlebarWidth = titleRect.size.width;
  BOOL isActive = (inputState == 0);  // 0 = key window (active)

  workRect = titleRect;
  workRect.origin.x -= 0.5;
  workRect.origin.y -= 0.5;
  [self drawTitleBarBackground:workRect];

  // Draw edge buttons
  if (styleMask & NSClosableWindowMask)
    {
      NSRect closeRect = [self closeButtonRectForTitlebarWidth:titlebarWidth];
      closeRect.origin.y += titleRect.origin.y;
      [self drawCloseButtonInRect:closeRect state:GSThemeNormalState active:isActive];
    }

  if (styleMask & NSMiniaturizableWindowMask)
    {
      NSRect minRect;
      if (styleMask & NSResizableWindowMask) {
        minRect = [self minimizeButtonRectForTitlebarWidth:titlebarWidth];
      } else {
        // Solo minimize: position at right edge
        minRect = NSMakeRect(titlebarWidth - METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, 0,
                             METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, METRICS_TITLEBAR_HEIGHT);
      }
      minRect.origin.y += titleRect.origin.y;
      [self drawMinimizeButtonInRect:minRect state:GSThemeNormalState active:isActive];
    }

  if (styleMask & NSResizableWindowMask)
    {
      NSRect zoomRect = [self maximizeButtonRectForTitlebarWidth:titlebarWidth];
      zoomRect.origin.y += titleRect.origin.y;
      [self drawMaximizeButtonInRect:zoomRect state:GSThemeNormalState active:isActive];
    }

  // Draw the title.
  if (styleMask & NSTitledWindowMask)
    {
      NSSize titleSize;
      workRect = titleRect;

      if (EauTitleBarButtonStyleIsOrb()) {
        // Orb style: all buttons on left, reserve orb region
        workRect.origin.x += METRICS_TITLEBAR_ORB_REGION_WIDTH;
        workRect.size.width -= METRICS_TITLEBAR_ORB_REGION_WIDTH;
      } else {
        // Edge style: close on left, minimize+maximize on right
        if (styleMask & NSClosableWindowMask)
          {
            workRect.origin.x += METRICS_TITLEBAR_EDGE_BUTTON_WIDTH;
            workRect.size.width -= METRICS_TITLEBAR_EDGE_BUTTON_WIDTH;
          }
        if ((styleMask & NSMiniaturizableWindowMask) && (styleMask & NSResizableWindowMask))
          {
            workRect.size.width -= METRICS_TITLEBAR_RIGHT_REGION_WIDTH;  // two buttons
          }
        else if ((styleMask & NSMiniaturizableWindowMask) || (styleMask & NSResizableWindowMask))
          {
            workRect.size.width -= METRICS_TITLEBAR_EDGE_BUTTON_WIDTH;   // one button
          }
      }

      titleSize = [title sizeWithAttributes: titleTextAttributes[attrIndex]];
      if (titleSize.width <= workRect.size.width)
        {
          if (EauTitleBarButtonStyleIsOrb()) {
            // Center in full titlebar width, clamp to not overlap orb region
            CGFloat centeredX = titleRect.origin.x + titleRect.size.width / 2.0 - titleSize.width / 2.0;
            workRect.origin.x = MAX(centeredX, titleRect.origin.x + METRICS_TITLEBAR_ORB_REGION_WIDTH);
          } else {
            CGFloat centeredX = titleRect.origin.x + titleRect.size.width / 2.0 - titleSize.width / 2.0;
            CGFloat minX = workRect.origin.x;
            CGFloat maxX = NSMaxX(workRect) - titleSize.width;
            workRect.origin.x = MAX(minX, MIN(centeredX, maxX));
          }
        }
      workRect.origin.y = NSMidY(workRect) - titleSize.height / 2;
      workRect.size.height = titleSize.height;
      [title drawInRect: workRect
          withAttributes: titleTextAttributes[attrIndex]];
    }
}

- (void) drawTitleBarBackground: (NSRect)rect {

  NSColor* borderColor = [Eau controlStrokeColor];
  NSGradient* gradient = [self _windowTitlebarGradient];

  CGFloat titleBarCornerRadius = METRICS_TITLEBAR_CORNER_RADIUS;
  NSRect titleRect = rect;
  titleRect.origin.x += 1;
  titleRect.size.width -= 1;
  NSRectFillUsingOperation(titleRect, NSCompositeClear);
  NSRect titleinner = NSInsetRect(titleRect, titleBarCornerRadius, titleBarCornerRadius);
  NSBezierPath* titleBarPath = [NSBezierPath bezierPath];
  [titleBarPath moveToPoint: NSMakePoint(NSMinX(titleRect), NSMinY(titleRect))];
  [titleBarPath lineToPoint: NSMakePoint(NSMaxX(titleRect), NSMinY(titleRect))];
  [titleBarPath appendBezierPathWithArcWithCenter: NSMakePoint(NSMaxX(titleinner), NSMaxY(titleinner))
                                           radius: titleBarCornerRadius
                                       startAngle: 0
                                         endAngle: 90];
  [titleBarPath appendBezierPathWithArcWithCenter: NSMakePoint(NSMinX(titleinner), NSMaxY(titleinner))
                                           radius: titleBarCornerRadius
                                       startAngle: 90
                                         endAngle: 180];
  [titleBarPath closePath];

  NSBezierPath* linePath = [NSBezierPath bezierPath];
  [linePath moveToPoint: NSMakePoint(NSMinX(titleRect), NSMinY(titleRect)+1)];
  [linePath lineToPoint:  NSMakePoint(NSMaxX(titleRect), NSMinY(titleRect)+1)];

  [borderColor setStroke];
  [gradient drawInBezierPath: titleBarPath angle: -90];
  [titleBarPath setLineWidth: 1];
  [titleBarPath stroke];
  [linePath setLineWidth: 1];
  [linePath stroke];
}

- (NSColor *) windowFrameBorderColor
{
  return [Eau controlStrokeColor];
}

- (void) drawResizeBarRect: (NSRect)resizeBarRect
{
  //I don't want to draw the resize bar
  //TODO change the mouse cursor on hover
}

- (void)prepareTitleTextAttributes
{

  NSMutableParagraphStyle *p;
  NSColor *keyColor, *normalColor, *mainColor;

  p = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
  [p setLineBreakMode: NSLineBreakByClipping];


  keyColor = [NSColor colorWithCalibratedRed: 0.1 green: 0.1 blue: 0.1 alpha: 1];
  normalColor = [NSColor colorWithCalibratedRed: 0.50 green: 0.50 blue: 0.50 alpha: 1];  // Lighter for unfocused
  mainColor = keyColor;

  titleTextAttributes[0] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
      [NSFont systemFontOfSize: 0], NSFontAttributeName,
      keyColor, NSForegroundColorAttributeName,
      p, NSParagraphStyleAttributeName,
      nil];

  titleTextAttributes[1] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
    [NSFont systemFontOfSize: 0], NSFontAttributeName,
    normalColor, NSForegroundColorAttributeName,
    p, NSParagraphStyleAttributeName,
    nil];

  titleTextAttributes[2] = [[NSMutableDictionary alloc]
    initWithObjectsAndKeys:
    [NSFont systemFontOfSize: 0], NSFontAttributeName,
    mainColor, NSForegroundColorAttributeName,
    p, NSParagraphStyleAttributeName,
    nil];
}



@end
