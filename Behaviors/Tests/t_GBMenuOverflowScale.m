/* t_GBMenuOverflowScale.m - a menu taller than the screen scrolls inside a
 * window that fits between the menu bar and the bottom of the screen, also
 * at a GSScaleFactor other than 1.
 *
 * Window frames and the screen are device pixels; the menu view and the
 * scroll manager's heights are points.  At 1.1 they used to be mixed: the
 * window reached over the menu bar and below the screen (bottom arrow and
 * last items unreachable), and on a desktop the frame never matched what
 * was asked for, so the overflow setup recursed until Menu.app crashed.
 *
 * Runs with the plain GNUstep theme and no GSAppKitUserBundles, so neither
 * the installed Eau theme nor the installed GershwinBehaviors bundle loads
 * its own copy of the scroll manager into this process.  Needs DISPLAY.
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import "Testing.h"
#import "GBMenuScrollManager.h"

@interface NSMenuView (TestHelper)
- (CGFloat) totalHeight;
- (CGFloat) yOriginForItem: (NSInteger)item;
@end

int main(int argc, char **argv)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  const CGFloat scale = 1.1;
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *args = [NSMutableDictionary dictionaryWithDictionary:
    [defs volatileDomainForName: NSArgumentDomain]];
  [args setObject: @"1.1" forKey: @"GSScaleFactor"];
  [args setObject: @"GNUstep" forKey: @"GSTheme"];
  [args setObject: [NSArray array] forKey: @"GSAppKitUserBundles"];
  [defs removeVolatileDomainForName: NSArgumentDomain];
  [defs setVolatileDomain: args forName: NSArgumentDomain];
  [NSApplication sharedApplication];

  NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Stations"];
  int i;
  for (i = 0; i < 80; i++)
    [menu addItemWithTitle: [NSString stringWithFormat: @"Station %d", i]
                    action: NULL keyEquivalent: @""];
  NSMenuView *view = (NSMenuView *)[menu menuRepresentation];
  [menu sizeToFit];
  NSWindow *window = [view window];
  NSRect screen = [[NSScreen mainScreen] frame];
  CGFloat menuBar = ([[GSTheme theme] menuBarHeight] + 2) * scale;
  /* Opened from the menu bar: its top at the bottom of the bar */
  NSRect frame = [window frame];
  frame.origin.y = NSMaxY(screen) - menuBar - NSHeight(frame);
  [window setFrame: frame display: NO];

  START_SET("overflow at scale 1.1")
    PASS(fabs([window userSpaceScaleFactor] - scale) < 0.001,
         "the window is scaled (%f)", [window userSpaceScaleFactor]);
    PASS([view totalHeight] * scale > NSHeight(screen),
         "the menu is taller than the screen");
    PASS([GBMenuScrollManager setupOverflowForMenuView: view],
         "overflow scrolling is set up");

    NSRect f = [window frame];
    PASS(NSMinY(f) >= NSMinY(screen) - 0.5,
         "the window does not reach below the screen (bottom %f)", NSMinY(f));
    PASS(NSMaxY(f) <= NSMaxY(screen) - menuBar + 0.5,
         "nor over the menu bar (top %f, bar from %f)", NSMaxY(f),
         NSMaxY(screen) - menuBar);

    GBMenuScrollManager *mgr = [GBMenuScrollManager scrollManagerForMenuView: view];
    CGFloat viewHeight = NSHeight([view frame]);
    PASS(fabs(viewHeight * scale - NSHeight(f)) <= 1.0,
         "the menu view fills the window (%f pt = %f px, window %f px)",
         viewHeight, viewHeight * scale, NSHeight(f));
    PASS(fabs([mgr visibleHeight] - viewHeight) < 0.01,
         "the viewport is the view's height in points (%f)", [mgr visibleHeight]);
    PASS(fabs([mgr maxScrollOffset] - ([view totalHeight] - viewHeight)) < 0.01,
         "scrolling reaches the whole menu");

    /* Scrolled to the bottom, the last item sits inside the viewport */
    [mgr setScrollOffset: 0];
    CGFloat lastY = [view yOriginForItem: [menu numberOfItems] - 1] - [mgr scrollOffset];
    PASS(lastY >= 0 && lastY < viewHeight, "the last item can be scrolled into view");

    /* Setting up again changes nothing: the setup is re-run from the
       menu window's frame setters, and must settle */
    NSRect before = [window frame];
    [GBMenuScrollManager setupOverflowForMenuView: view];
    PASS(NSEqualRects(before, [window frame]), "setting up again leaves the window alone");
  END_SET("overflow at scale 1.1")

  START_SET("a submenu opened lower down")
    NSMenu *sub = [[NSMenu alloc] initWithTitle: @"More"];
    for (i = 0; i < 80; i++)
      [sub addItemWithTitle: [NSString stringWithFormat: @"Item %d", i]
                     action: NULL keyEquivalent: @""];
    NSMenuView *subView = (NSMenuView *)[sub menuRepresentation];
    [sub sizeToFit];
    NSWindow *subWindow = [subView window];
    CGFloat itemTop = NSMinY(screen) + 0.5 * NSHeight(screen);
    NSRect sf = [subWindow frame];
    sf.origin.y = itemTop - NSHeight(sf);
    [subWindow setFrame: sf display: NO];

    PASS([GBMenuScrollManager setupOverflowForMenuView: subView], "it scrolls too");
    sf = [subWindow frame];
    PASS(fabs(NSMaxY(sf) - itemTop) <= 1.0,
         "it hangs down from where it was opened (top %f, item %f)", NSMaxY(sf), itemTop);
    PASS(NSMinY(sf) >= NSMinY(screen) - 0.5, "and ends at the bottom of the screen");
  END_SET("a submenu opened lower down")

  [arp release];
  return 0;
}
