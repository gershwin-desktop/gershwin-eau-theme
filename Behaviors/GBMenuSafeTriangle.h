/* GBMenuSafeTriangle.h - geometry of the menu "safe triangle"
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* Plain C on Foundation types so the unit test runs without AppKit or a
 * display.  All rects and points are in screen coordinates (GNUstep: y
 * grows upward). */

/* Which side of its parent item a submenu window was placed on.  libs-gui
 * and Eau flip vertical submenus to the left at the screen edge, and menu
 * bar dropdowns open below (or above when there is no room). */
typedef enum {
  GBSubmenuSideRight = 0,
  GBSubmenuSideLeft,
  GBSubmenuSideBelow,
  GBSubmenuSideAbove
} GBSubmenuSide;

typedef struct {
  NSPoint apex;  /* where the pointer left the parent item */
  NSPoint near1; /* the two corners of the submenu edge facing the item */
  NSPoint near2;
} GBSafeTriangle;

GBSubmenuSide GBSubmenuSideForRects(NSRect itemRect, NSRect submenuRect, BOOL horizontal);

GBSafeTriangle GBSafeTriangleMake(NSPoint apex, NSRect itemRect, NSRect submenuRect,
                                  BOOL horizontal);

/* Points on an edge count as inside: a pointer sliding exactly along the
 * diagonal toward a submenu corner must not flicker the highlight.  A
 * degenerate triangle (apex on the submenu edge line) contains nothing. */
BOOL GBPointInSafeTriangle(NSPoint p, GBSafeTriangle t);
