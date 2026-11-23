/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* Where an NSDrawer's window goes and how it is shaped.  Pure geometry, so
 * it is tested without a display.  Frames are AppKit screen coordinates
 * (y up); edges are NSRectEdge, the parent's edge the drawer comes out of. */
@interface EauDrawerGeometry : NSObject

/* The open drawer's frame: flush against the parent's edge, spanning the
 * parent's content side less the leading offset (top of a side edge, left
 * end of a top or bottom edge) and the trailing one, and as thick as the
 * content plus the drawer margin on both sides.  libs-gui sizes the drawer
 * from a box laid out at the parent's size instead, which makes it as wide
 * as the parent or wider. */
+ (NSRect) frameForEdge: (NSRectEdge)edge
            parentFrame: (NSRect)parentFrame
          parentContent: (NSRect)parentContent
            contentSize: (NSSize)contentSize
                leading: (CGFloat)leading
               trailing: (CGFloat)trailing
                 margin: (CGFloat)margin;

/* Where the drawer's content box goes inside its window's bounds. */
+ (NSRect) contentRectForBounds: (NSRect)bounds margin: (CGFloat)margin;

/* The side of the drawer's own bounds (y up) that meets the parent. */
+ (NSRectEdge) seamEdgeForEdge: (NSRectEdge)edge;

/* The drawer's outline for the window manager's _WM_SHAPE_PATH property
 * (version 1, then commands with 16.16 points, y down): a rectangle with
 * the two corners away from the parent rounded by radius pixels. */
+ (NSData *) shapePathForEdge: (NSRectEdge)edge radius: (CGFloat)radius;

@end
