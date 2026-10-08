/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauDrawerGeometry.h"
#include <math.h>

/* How far along a quarter circle's tangents a cubic Bezier's control points
 * lie, as a share of the radius. */
static const double EAUCircleControl = 0.5523;

/* A _WM_SHAPE_PATH point: x = fx * width + ox, y = fy * height + oy. */
typedef struct {
  double fx, ox, fy, oy;
} EAUShapePoint;

static EAUShapePoint EAUMovedPoint(EAUShapePoint p, double dx, double dy)
{
  p.ox += dx;
  p.oy += dy;
  return p;
}

static void EAUAppendPoint(NSMutableData *path, EAUShapePoint p)
{
  int32_t v[4];
  v[0] = (int32_t)lround(p.fx * 65536.0);
  v[1] = (int32_t)lround(p.ox * 65536.0);
  v[2] = (int32_t)lround(p.fy * 65536.0);
  v[3] = (int32_t)lround(p.oy * 65536.0);
  [path appendBytes: v length: sizeof(v)];
}

static void EAUAppendCommand(NSMutableData *path, int32_t command)
{
  [path appendBytes: &command length: sizeof(command)];
}

@implementation EauDrawerGeometry

+ (NSRect) frameForEdge: (NSRectEdge)edge
            parentFrame: (NSRect)parentFrame
          parentContent: (NSRect)parentContent
            contentSize: (NSSize)contentSize
                leading: (CGFloat)leading
               trailing: (CGFloat)trailing
                 margin: (CGFloat)margin
{
  if (edge == NSMinXEdge || edge == NSMaxXEdge)
    {
      CGFloat width = contentSize.width + 2.0 * margin;
      CGFloat height = MAX(1.0, NSHeight(parentContent) - leading - trailing);
      CGFloat x = (edge == NSMaxXEdge) ? NSMaxX(parentFrame) : NSMinX(parentFrame) - width;

      /* y up: the leading offset is measured down from the content's top. */
      return NSMakeRect(x, NSMinY(parentContent) + trailing, width, height);
    }
  else
    {
      CGFloat height = contentSize.height + 2.0 * margin;
      CGFloat width = MAX(1.0, NSWidth(parentContent) - leading - trailing);
      CGFloat y = (edge == NSMinYEdge) ? NSMinY(parentFrame) - height : NSMaxY(parentFrame);

      return NSMakeRect(NSMinX(parentContent) + leading, y, width, height);
    }
}

+ (NSRect) contentRectForBounds: (NSRect)bounds margin: (CGFloat)margin
{
  return NSInsetRect(bounds, margin, margin);
}

+ (NSRectEdge) seamEdgeForEdge: (NSRectEdge)edge
{
  switch (edge)
    {
      case NSMinXEdge: return NSMaxXEdge;
      case NSMaxXEdge: return NSMinXEdge;
      case NSMinYEdge: return NSMaxYEdge;
      default:         return NSMinYEdge;
    }
}

+ (NSData *) shapePathForEdge: (NSRectEdge)edge radius: (CGFloat)radius
{
  /* Corners clockwise from the top left, y down, and the way the outline
   * arrives at and leaves each. */
  static const EAUShapePoint corners[4] = {
    { 0, 0, 0, 0 }, { 1, 0, 0, 0 }, { 1, 0, 1, 0 }, { 0, 0, 1, 0 }
  };
  static const double arrive[4][2] = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } };
  static const double leave[4][2] = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } };
  /* The corners away from the parent: y down, a drawer below its parent
   * (NSMinYEdge) is rounded at the bottom. */
  BOOL rounded[4] = { NO, NO, NO, NO };
  NSMutableData *path = [NSMutableData data];
  int32_t version = 1;
  EAUShapePoint in[4], out[4];
  int i;

  switch (edge)
    {
      case NSMaxXEdge: rounded[1] = rounded[2] = YES; break;
      case NSMinXEdge: rounded[0] = rounded[3] = YES; break;
      case NSMinYEdge: rounded[2] = rounded[3] = YES; break;
      default:         rounded[0] = rounded[1] = YES; break;
    }
  for (i = 0; i < 4; i++)
    {
      in[i] = EAUMovedPoint(corners[i], -arrive[i][0] * radius, -arrive[i][1] * radius);
      out[i] = EAUMovedPoint(corners[i], leave[i][0] * radius, leave[i][1] * radius);
    }

  [path appendBytes: &version length: sizeof(version)];
  EAUAppendCommand(path, 0);
  EAUAppendPoint(path, rounded[0] ? out[0] : corners[0]);
  for (i = 1; i <= 4; i++)
    {
      int c = i % 4;
      if (rounded[c])
        {
          double k = radius * EAUCircleControl;
          EAUAppendCommand(path, 1);
          EAUAppendPoint(path, in[c]);
          EAUAppendCommand(path, 2);
          EAUAppendPoint(path, EAUMovedPoint(in[c], arrive[c][0] * k, arrive[c][1] * k));
          EAUAppendPoint(path, EAUMovedPoint(out[c], -leave[c][0] * k, -leave[c][1] * k));
          EAUAppendPoint(path, out[c]);
        }
      else if (c != 0)
        {
          EAUAppendCommand(path, 1);
          EAUAppendPoint(path, corners[c]);
        }
    }
  EAUAppendCommand(path, 3);
  return path;
}

@end
