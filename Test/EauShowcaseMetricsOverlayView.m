/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauShowcaseMetricsOverlayView.h"

@implementation EauShowcaseMetricsAnnotation

+ (instancetype)annotationWithRect: (NSRect)rect
                              label: (NSString *)label
                              color: (NSColor *)color
{
  EauShowcaseMetricsAnnotation *annotation = [[self alloc] init];
  annotation->_rect = rect;
  annotation->_label = [label copy];
  annotation->_color = color;
  return annotation;
}

@end

@implementation EauShowcaseMetricsOverlayView

- (BOOL)isOpaque
{
  return NO;
}

/* This view exists only to be looked at, never clicked - let every event
 * fall through to whatever it is annotating. */
- (NSView *)hitTest: (NSPoint)point
{
  return nil;
}

- (void)setAnnotations: (NSArray *)annotations
{
  _annotations = [annotations copy];
  [self setNeedsDisplay: YES];
}

- (void)drawRect: (NSRect)dirtyRect
{
  NSDictionary *labelAttributes = @{
    NSFontAttributeName: [NSFont systemFontOfSize: 10],
    NSForegroundColorAttributeName: [NSColor blackColor]
  };

  for (EauShowcaseMetricsAnnotation *annotation in _annotations)
    {
      NSRect rect = [annotation rect];
      NSColor *color = [annotation color];

      [[color colorWithAlphaComponent: 0.22] set];
      NSRectFillUsingOperation(rect, NSCompositeSourceOver);
      [[color colorWithAlphaComponent: 0.85] set];
      NSFrameRectWithWidth(rect, 1.0);

      NSString *label = [annotation label];
      if ([label length] == 0)
        continue;

      NSSize textSize = [label sizeWithAttributes: labelAttributes];
      NSPoint labelOrigin = NSMakePoint(
        NSMinX(rect) + 2, NSMaxY(rect) + 2);
      /* Keep the label inside the view when the annotated rect sits at
       * the top edge - AppearanceMetrics rects for margins commonly do. */
      if (labelOrigin.y + textSize.height > NSMaxY([self bounds]))
        labelOrigin.y = NSMinY(rect) - textSize.height - 2;

      NSRect labelBackground = NSMakeRect(
        labelOrigin.x - 2, labelOrigin.y - 1, textSize.width + 4, textSize.height + 2);
      [[[NSColor whiteColor] colorWithAlphaComponent: 0.85] set];
      NSRectFillUsingOperation(labelBackground, NSCompositeSourceOver);

      [label drawAtPoint: labelOrigin withAttributes: labelAttributes];
    }
}

@end
