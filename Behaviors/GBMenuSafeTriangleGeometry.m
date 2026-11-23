/* GBMenuSafeTriangleGeometry.m - pure geometry for GBMenuSafeTriangle.m
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBMenuSafeTriangle.h"

GBSubmenuSide GBSubmenuSideForRects(NSRect itemRect, NSRect submenuRect, BOOL horizontal)
{
  /* Compare centres rather than edges: a flipped or shifted submenu may
   * overlap its parent by a few pixels, which edge tests misread. */
  if (horizontal) {
    return NSMidY(submenuRect) <= NSMidY(itemRect) ? GBSubmenuSideBelow : GBSubmenuSideAbove;
  }
  return NSMidX(submenuRect) >= NSMidX(itemRect) ? GBSubmenuSideRight : GBSubmenuSideLeft;
}

GBSafeTriangle GBSafeTriangleMake(NSPoint apex, NSRect itemRect, NSRect submenuRect,
                                  BOOL horizontal)
{
  GBSafeTriangle t;
  CGFloat minX = NSMinX(submenuRect), maxX = NSMaxX(submenuRect);
  CGFloat minY = NSMinY(submenuRect), maxY = NSMaxY(submenuRect);

  t.apex = apex;
  switch (GBSubmenuSideForRects(itemRect, submenuRect, horizontal)) {
    case GBSubmenuSideRight:
      t.near1 = NSMakePoint(minX, minY);
      t.near2 = NSMakePoint(minX, maxY);
      break;
    case GBSubmenuSideLeft:
      t.near1 = NSMakePoint(maxX, minY);
      t.near2 = NSMakePoint(maxX, maxY);
      break;
    case GBSubmenuSideBelow:
      t.near1 = NSMakePoint(minX, maxY);
      t.near2 = NSMakePoint(maxX, maxY);
      break;
    case GBSubmenuSideAbove:
    default:
      t.near1 = NSMakePoint(minX, minY);
      t.near2 = NSMakePoint(maxX, minY);
      break;
  }
  return t;
}

static CGFloat cross(NSPoint o, NSPoint a, NSPoint b)
{
  return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

BOOL GBPointInSafeTriangle(NSPoint p, GBSafeTriangle t)
{
  CGFloat area = cross(t.apex, t.near1, t.near2);
  if (area == 0) {
    return NO;
  }

  CGFloat d1 = cross(t.apex, t.near1, p);
  CGFloat d2 = cross(t.near1, t.near2, p);
  CGFloat d3 = cross(t.near2, t.apex, p);

  /* Inside (or on an edge) when p is on the same side of all three edges;
   * the sign depends on the winding, which varies with the submenu side. */
  BOOL hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
  BOOL hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
  return !(hasNeg && hasPos);
}
