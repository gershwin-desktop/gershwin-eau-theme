/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauDrawerGeometry.h"

@implementation EauDrawerGeometry

+ (NSRect) frameForEdge: (NSRectEdge)edge
            parentFrame: (NSRect)parentFrame
          parentContent: (NSRect)parentContent
            contentSize: (NSSize)contentSize
                leading: (CGFloat)leading
               trailing: (CGFloat)trailing
                 margin: (CGFloat)margin
{
  return NSZeroRect;
}

+ (NSRect) contentRectForBounds: (NSRect)bounds margin: (CGFloat)margin
{
  return bounds;
}

+ (NSRectEdge) seamEdgeForEdge: (NSRectEdge)edge
{
  return edge;
}

+ (NSData *) shapePathForEdge: (NSRectEdge)edge radius: (CGFloat)radius
{
  return [NSData data];
}

@end
