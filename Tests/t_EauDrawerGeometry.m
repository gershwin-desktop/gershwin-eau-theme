/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Where the theme puts an NSDrawer's window and how it outlines it.
 * Headless: pure geometry. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "EauDrawerGeometry.h"

static BOOL near(double a, double b)
{
  return fabs(a - b) < 1e-9;
}

/* 16.16 fixed point, as _WM_SHAPE_PATH stores it. */
static int32_t fx(double v)
{
  return (int32_t)lround(v * 65536.0);
}

/* Is (fx, ox, fy, oy) one of the path's points? */
static BOOL hasPoint(NSData *path, double f1, double o1, double f2, double o2)
{
  const int32_t *v = [path bytes];
  NSUInteger n = [path length] / 4;
  NSUInteger i;
  for (i = 1; i + 3 < n; i++)
    {
      if (v[i] == fx(f1) && v[i + 1] == fx(o1) && v[i + 2] == fx(f2) && v[i + 3] == fx(o2))
        return YES;
    }
  return NO;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* A parent with its content 22 below the frame's top (y up). */
  NSRect frame = NSMakeRect(200, 100, 600, 422);
  NSRect content = NSMakeRect(200, 100, 600, 400);
  NSSize size = NSMakeSize(160, 120);

  START_SET("frame")
    NSRect r = [EauDrawerGeometry frameForEdge: NSMaxXEdge parentFrame: frame
                                 parentContent: content contentSize: size
                                       leading: 0 trailing: 10 margin: 6];
    PASS(near(NSMinX(r), NSMaxX(frame)) && near(NSWidth(r), 160 + 12),
         "a right drawer is flush with the right edge, content plus two margins wide");
    PASS(near(NSMaxY(r), NSMaxY(content)) && near(NSMinY(r), NSMinY(content) + 10),
         "its top is the content's top less leading, its bottom the trailing offset up");

    NSRect l = [EauDrawerGeometry frameForEdge: NSMinXEdge parentFrame: frame
                                 parentContent: content contentSize: size
                                       leading: 5 trailing: 10 margin: 6];
    PASS(near(NSMaxX(l), NSMinX(frame)) && near(NSHeight(l), 400 - 15),
         "a left drawer ends at the left edge");

    NSRect b = [EauDrawerGeometry frameForEdge: NSMinYEdge parentFrame: frame
                                 parentContent: content contentSize: size
                                       leading: 10 trailing: 20 margin: 6];
    PASS(near(NSMaxY(b), NSMinY(frame)) && near(NSHeight(b), 120 + 12),
         "a bottom drawer hangs below the frame, content plus two margins high");
    PASS(near(NSMinX(b), NSMinX(content) + 10) && near(NSWidth(b), 600 - 30),
         "it spans the content's width less the offsets");

    NSRect t = [EauDrawerGeometry frameForEdge: NSMaxYEdge parentFrame: frame
                                 parentContent: content contentSize: size
                                       leading: 10 trailing: 20 margin: 6];
    PASS(near(NSMinY(t), NSMaxY(frame)), "a top drawer sits above the frame");

    NSRect tiny = [EauDrawerGeometry frameForEdge: NSMaxXEdge parentFrame: frame
                                    parentContent: content contentSize: size
                                          leading: 300 trailing: 300 margin: 6];
    PASS(NSHeight(tiny) >= 1, "offsets longer than the parent never make it vanish");
  END_SET("frame")

  START_SET("content and seam")
    NSRect c = [EauDrawerGeometry contentRectForBounds: NSMakeRect(0, 0, 172, 390) margin: 6];
    PASS(NSEqualRects(c, NSMakeRect(6, 6, 160, 378)), "the content is inset by the margin");
    PASS([EauDrawerGeometry seamEdgeForEdge: NSMaxXEdge] == NSMinXEdge
         && [EauDrawerGeometry seamEdgeForEdge: NSMinXEdge] == NSMaxXEdge
         && [EauDrawerGeometry seamEdgeForEdge: NSMinYEdge] == NSMaxYEdge
         && [EauDrawerGeometry seamEdgeForEdge: NSMaxYEdge] == NSMinYEdge,
         "the seam is the drawer's side facing the parent");
  END_SET("content and seam")

  START_SET("outline")
    NSData *right = [EauDrawerGeometry shapePathForEdge: NSMaxXEdge radius: 5];
    const int32_t *v = [right bytes];
    PASS([right length] > 8 && v[0] == 1, "a version 1 path");
    PASS(hasPoint(right, 0, 0, 0, 0) && hasPoint(right, 0, 0, 1, 0),
         "a right drawer keeps square corners at the parent (left) side");
    PASS(!hasPoint(right, 1, 0, 0, 0) && !hasPoint(right, 1, 0, 1, 0),
         "its outer corners are cut");
    PASS(hasPoint(right, 1, -5, 0, 0) && hasPoint(right, 1, 0, 0, 5),
         "and rounded with the radius at the top right");
    PASS(hasPoint(right, 1, 0, 1, -5) && hasPoint(right, 1, -5, 1, 0),
         "and at the bottom right");

    NSData *bottom = [EauDrawerGeometry shapePathForEdge: NSMinYEdge radius: 5];
    PASS(hasPoint(bottom, 0, 0, 0, 0) && hasPoint(bottom, 1, 0, 0, 0)
         && !hasPoint(bottom, 0, 0, 1, 0) && !hasPoint(bottom, 1, 0, 1, 0),
         "a bottom drawer is rounded at its lower corners (y down), square at the top");

    NSData *left = [EauDrawerGeometry shapePathForEdge: NSMinXEdge radius: 5];
    PASS(hasPoint(left, 1, 0, 0, 0) && !hasPoint(left, 0, 0, 0, 0),
         "a left drawer is rounded on its left");
  END_SET("outline")

  [arp release];
  return 0;
}
