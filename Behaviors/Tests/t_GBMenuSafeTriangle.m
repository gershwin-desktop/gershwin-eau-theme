/*
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Coverage for the menu safe-triangle geometry: which side a submenu
 * opened on, which submenu corners form the triangle, and which pointer
 * positions keep the submenu open.  Screen coordinates, y grows upward. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GBMenuSafeTriangle.h"

int main(void)
{
  @autoreleasepool
    {
      /* Parent item: 200x20 at (100, 500) in a vertical menu. */
      NSRect item = NSMakeRect(100, 500, 200, 20);
      NSRect right = NSMakeRect(300, 380, 150, 140);
      NSRect left = NSMakeRect(-50, 380, 150, 140);

      /* --- side detection --- */
      PASS(GBSubmenuSideForRects(item, right, NO) == GBSubmenuSideRight,
           "submenu to the right");
      PASS(GBSubmenuSideForRects(item, left, NO) == GBSubmenuSideLeft,
           "submenu flipped to the left");
      PASS(GBSubmenuSideForRects(item, NSMakeRect(280, 380, 150, 140), NO)
             == GBSubmenuSideRight,
           "overlapping right submenu is still on the right");

      NSRect barItem = NSMakeRect(40, 1000, 60, 24);
      NSRect dropdown = NSMakeRect(40, 700, 180, 300);
      PASS(GBSubmenuSideForRects(barItem, dropdown, YES) == GBSubmenuSideBelow,
           "menu bar dropdown below");
      PASS(GBSubmenuSideForRects(NSMakeRect(40, 0, 60, 24), NSMakeRect(40, 24, 180, 300), YES)
             == GBSubmenuSideAbove,
           "menu bar dropdown above");

      /* --- corners --- */
      NSPoint apex = NSMakePoint(250, 505);
      GBSafeTriangle tr = GBSafeTriangleMake(apex, item, right, NO);
      PASS(NSEqualPoints(tr.apex, apex), "apex kept");
      PASS(tr.near1.x == 300 && tr.near2.x == 300 && tr.near1.y == 380 && tr.near2.y == 520,
           "right submenu: its left edge is the base");

      GBSafeTriangle tl = GBSafeTriangleMake(NSMakePoint(150, 505), item, left, NO);
      PASS(tl.near1.x == 100 && tl.near2.x == 100, "left submenu: its right edge is the base");

      GBSafeTriangle tb = GBSafeTriangleMake(NSMakePoint(70, 1010), barItem, dropdown, YES);
      PASS(tb.near1.y == 1000 && tb.near2.y == 1000 && tb.near1.x == 40 && tb.near2.x == 220,
           "dropdown below: its top edge is the base");

      /* --- right submenu: diagonal path down-right crosses items below --- */
      PASS(GBPointInSafeTriangle(NSMakePoint(270, 490), tr),
           "diagonal toward lower submenu corner is inside");
      PASS(GBPointInSafeTriangle(NSMakePoint(290, 420), tr), "near the submenu base is inside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(240, 490), tr),
           "straight down (away from submenu) is outside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(200, 505), tr), "moving left is outside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(310, 450), tr),
           "past the base (in the submenu) is outside the triangle");
      PASS(GBPointInSafeTriangle(apex, tr), "apex itself counts as inside");
      PASS(GBPointInSafeTriangle(NSMakePoint(275, 442.5), tr),
           "point on the lower edge counts as inside");

      /* --- left submenu: mirrored --- */
      PASS(GBPointInSafeTriangle(NSMakePoint(130, 490), tl),
           "diagonal toward a left submenu is inside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(170, 490), tl),
           "moving right, away from a left submenu, is outside");

      /* --- menu bar dropdown: bar item spans y 1000..1024 --- */
      PASS(GBPointInSafeTriangle(NSMakePoint(120, 1002), tb),
           "diagonal from bar item over its neighbour toward the dropdown is inside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(120, 1008), tb),
           "sideways along the bar is outside");
      PASS(!GBPointInSafeTriangle(NSMakePoint(70, 1015), tb), "moving up is outside");

      /* --- degenerate --- */
      GBSafeTriangle flat = GBSafeTriangleMake(NSMakePoint(300, 450), item, right, NO);
      PASS(!GBPointInSafeTriangle(NSMakePoint(300, 450), flat),
           "apex on the base line gives an empty triangle");
    }
  return 0;
}
