// NSMenuView+Eau.m
// Eau Theme NSMenuView Extensions

#import "Eau.h"
#import "NSMenuView+Eau.h"
#import <AppKit/NSMenuView.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

/* Forward-declare the slot-rect helper implemented in Eau.m so the
 * compiler knows the return type. */
@interface Eau (EauSlotRect)
+ (NSRect)_eauMenuSlotScreenRect;
@end

@implementation NSMenuView (EauTheme)

/* Swizzled -setHorizontal:. Default libs-gui implementation, when the
 * view becomes horizontal (main menu under NSMacintoshInterfaceStyle),
 * sets the view's frame to FULL screen width
 * (NSMenuView.m:343 — `[self setFrameSize: scRect.size]` with scRect =
 * [[NSScreen mainScreen] frame]). This frame later propagates to the
 * NSMenuPanel via NSMenu.sizeToFit and OVERRIDES our modifyRect:forMenu:
 * narrowing. To keep the bar inside Menu.app's slot, we re-size the
 * view to the slot width immediately after the original setHorizontal:
 * runs. */
- (void)eau_setHorizontal:(BOOL)flag
{
  [self eau_setHorizontal:flag];  // original (swap pointer)

  if (!flag) return;
  NSRect slot = [Eau _eauMenuSlotScreenRect];
  if (slot.size.width <= 0 || slot.size.height <= 0) return;

  NSSize newSize = NSMakeSize(slot.size.width, slot.size.height);
  [self setFrameSize:newSize];

  /* Force the panel hosting this NSMenuView above Menu.app's bar so it
   * always wins z-order in the slot region. setHidesOnDeactivate:NO
   * keeps the panel mapped even when the user clicks Menu.app's
   * command-menu icon (X11 focus briefly shifts to Menu.app); without
   * this the panel hides and the slot goes blank — the bar must stay
   * "locked" like macOS. */
  NSWindow *panel = [self window];
  if (!panel) return;
  [panel setLevel:NSMainMenuWindowLevel + 1];
  [panel setHidesOnDeactivate:NO];
  if ([panel respondsToSelector:@selector(setCanHide:)]) {
    [(id)panel setCanHide:NO];
  }

  /* Tell the WM this DOCK-typed window does NOT want any workarea
   * reserved on its behalf (Menu.app's strut already handles that for
   * the whole top strip). Without this, libs-back's
   * NSMainMenuWindowLevel → _NET_WM_WINDOW_TYPE_DOCK mapping causes the
   * WM to register a second strut and push the dock down. We don't try
   * to change the window type itself (libs-back rewrites it); we set
   * _NET_WM_STRUT_PARTIAL = all zeros which the WM honours. */
  GSDisplayServer *server = GSServerForWindow(panel);
  if (!server) return;
  Display *dpy = (Display *)[server serverDevice];
  Window xid = (Window)(uintptr_t)[server windowDevice:[panel windowNumber]];
  if (!dpy || xid == 0) return;
  Atom strutAtom        = XInternAtom(dpy, "_NET_WM_STRUT",         False);
  Atom strutPartialAtom = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
  long strut[4]      = {0, 0, 0, 0};
  long partial[12]   = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  XChangeProperty(dpy, xid, strutAtom,        XA_CARDINAL, 32, PropModeReplace,
                  (unsigned char *)strut,   4);
  XChangeProperty(dpy, xid, strutPartialAtom, XA_CARDINAL, 32, PropModeReplace,
                  (unsigned char *)partial, 12);
  XFlush(dpy);
}

- (NSPoint)eau_locationForSubmenu:(NSMenu *)aSubmenu
{
  EAULOG(@"NSMenuView+Eau: eau_locationForSubmenu: called for submenu %@", aSubmenu);

  NSMenuView *menuView = (NSMenuView *)self;

  // Call the original implementation - it correctly calculates Y position.
  // After swizzling, -eau_locationForSubmenu: points to the original
  // -locationForSubmenu: implementation.
  NSPoint originalPoint = [self eau_locationForSubmenu:aSubmenu];

  // If this menu view itself is horizontal (the menu bar), use original positioning entirely
  if ([menuView isHorizontal]) {
    EAULOG(@"NSMenuView+Eau: Menu is horizontal, using original submenu position {%.1f, %.1f}",
          originalPoint.x, originalPoint.y);
    return originalPoint;
  }

  // For vertical dropdown menus, adjust only the X position to remove overlap
  // Keep the original Y position which correctly aligns with the parent item
  NSWindow *window = [menuView window];
  if (!window) {
    EAULOG(@"NSMenuView+Eau: No window for menu view, using original submenu position {%.1f, %.1f}",
          originalPoint.x, originalPoint.y);
    return originalPoint;
  }

  NSRect frame = [window frame];

  // X position: right edge of parent menu window (just touching, no overlap)
  CGFloat xPos = NSMaxX(frame);

  // Y position: use the original calculation which correctly handles item position
  CGFloat yPos = originalPoint.y;

  EAULOG(@"NSMenuView+Eau: Adjusted submenu position from {%.1f, %.1f} to {%.1f, %.1f}",
        originalPoint.x, originalPoint.y, xPos, yPos);

  return NSMakePoint(xPos, yPos);
}

@end

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void) {
  // NSLog(@"NSMenuView+Eau: Constructor called - setting up swizzling");

  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass) {
    EAULOG(@"NSMenuView+Eau: ERROR - NSMenuView class not found");
    return;
  }

  // Swizzle locationForSubmenu: with eau_locationForSubmenu:
  SEL originalSelector = sel_registerName("locationForSubmenu:");
  SEL swizzledSelector = @selector(eau_locationForSubmenu:);

  Method originalMethod = class_getInstanceMethod(menuViewClass, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(menuViewClass, swizzledSelector);

  if (!originalMethod) {
    EAULOG(@"NSMenuView+Eau: ERROR - Could not find original locationForSubmenu: method");
    return;
  }

  if (!swizzledMethod) {
    EAULOG(@"NSMenuView+Eau: ERROR - Could not find eau_locationForSubmenu: method on NSMenuView");
    return;
  }

  // Avoid double-swizzling: if the IMPs are already the same, do nothing.
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP) {
    EAULOG(@"NSMenuView+Eau: Swizzling skipped - implementations already identical");
    return;
  }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  // NSLog(@"NSMenuView+Eau: Successfully swizzled locationForSubmenu: with eau_locationForSubmenu:");

  // Also swizzle setHorizontal: so that when the main menu's view becomes
  // horizontal we can clamp its frame to Menu.app's slot width instead of
  // letting libs-gui set it to full-screen width.
  SEL setHOrig = sel_registerName("setHorizontal:");
  SEL setHSwiz = @selector(eau_setHorizontal:);
  Method origH = class_getInstanceMethod(menuViewClass, setHOrig);
  Method swizH = class_getInstanceMethod(menuViewClass, setHSwiz);
  if (origH && swizH
      && method_getImplementation(origH) != method_getImplementation(swizH)) {
    method_exchangeImplementations(origH, swizH);
    NSLog(@"NSMenuView+Eau: swizzled setHorizontal: for slot-bar sizing");
  }
}
