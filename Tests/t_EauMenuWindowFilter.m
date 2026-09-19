/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* ObjectTesting coverage for EauMenuWindowFilter: which of Menu.app's
 * top-level X windows the stale-dropdown cleanup may withdraw/destroy.
 * Needs an X display; the windows are created unmapped, so nothing shows up
 * on screen. */

#import <Foundation/Foundation.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>
#import "Testing.h"
#import "EauMenuWindowFilter.h"

/* Style masks as libs-back publishes them in _GNUSTEP_WM_ATTR. */
enum { kNoAttrs = -1, kBorderless = 0, kTitledClosable = 0x3 };

static Window makeWindow(Display *dpy, const char *resName,
                         const char *resClass, const char *typeName,
                         long style)
{
  Window w = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy),
                                 0, 0, 10, 10, 0, 0, 0);
  XClassHint hint;
  hint.res_name = (char *)resName;
  hint.res_class = (char *)resClass;
  XSetClassHint(dpy, w, &hint);
  if (typeName != NULL)
    {
      Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
      Atom type = XInternAtom(dpy, typeName, False);
      XChangeProperty(dpy, w, wmType, XA_ATOM, 32, PropModeReplace,
                      (unsigned char *)&type, 1);
    }
  if (style != kNoAttrs)
    {
      /* flags (style + level set), window_style, window_level */
      unsigned long attrs[3] = { 0x3, (unsigned long)style, 3 };
      Atom attrAtom = XInternAtom(dpy, "_GNUSTEP_WM_ATTR", False);
      XChangeProperty(dpy, w, attrAtom, attrAtom, 32, PropModeReplace,
                      (unsigned char *)attrs, 3);
    }
  XSync(dpy, False);
  return w;
}

int main(void)
{
  @autoreleasepool
    {
      /* --- utility height limit follows the scale factor --- */
      PASS(EauMenuUtilityHeightLimit(22, 1.0) == 22,
           "limit is the bar height at scale 1.0");
      PASS(EauMenuUtilityHeightLimit(22, 1.09f) == 24,
           "limit covers the 24px bar at scale 1.09");
      PASS(EauMenuUtilityHeightLimit(22, 1.1f) == 25,
           "limit rounds up so a 24.2pt search panel is covered");
      PASS(EauMenuUtilityHeightLimit(22, 1.25f) == 28,
           "limit at scale 1.25");
      PASS(EauMenuUtilityHeightLimit(22, 2.0) == 44,
           "limit at scale 2.0");

      Display *dpy = XOpenDisplay(NULL);
      PASS(dpy != NULL, "X display available (set DISPLAY)");
      if (dpy == NULL)
        return 0;

      Window bar = makeWindow(dpy, "Menu", "Menu", "_NET_WM_WINDOW_TYPE_DOCK",
                              kBorderless);
      Window dropdown = makeWindow(dpy, "Menu", "Menu", NULL, kBorderless);
      Window typedDropdown = makeWindow(dpy, "Menu", "Menu",
                                        "_NET_WM_WINDOW_TYPE_MENU",
                                        kBorderless);
      Window searchPanel = makeWindow(dpy, "Menu", "Menu",
                                      "_NET_WM_WINDOW_TYPE_DIALOG",
                                      kBorderless);
      Window otherApp = makeWindow(dpy, "TextEdit", "TextEdit", NULL,
                                   kBorderless);
      Window titledPanel = makeWindow(dpy, "Menu", "Menu", NULL,
                                      kTitledClosable);
      Window unknown = makeWindow(dpy, "Menu", "Menu", NULL, kNoAttrs);

      /* --- the menu bar is never a dropdown --- */
      PASS(EauIsMenuDropdownWindow(dpy, bar, 24, 22) == NO,
           "24px menu bar survives when scaled above the 22px limit");
      PASS(EauIsMenuDropdownWindow(dpy, bar, 44, 44) == NO,
           "menu bar at scale 2.0 is not a dropdown");
      PASS(EauIsMenuDropdownWindow(dpy, bar, 300, 22) == NO,
           "menu bar is protected by its DOCK type, not by its height");

      /* --- real dropdowns are still cleaned up --- */
      PASS(EauIsMenuDropdownWindow(dpy, dropdown, 135, 22) == YES,
           "untyped dropdown panel is a dropdown");
      PASS(EauIsMenuDropdownWindow(dpy, dropdown, 135, 25) == YES,
           "untyped dropdown panel is a dropdown at scale 1.1");
      PASS(EauIsMenuDropdownWindow(dpy, typedDropdown, 135, 22) == YES,
           "MENU-typed dropdown panel is a dropdown");

      /* --- small utility windows are not dropdowns --- */
      PASS(EauIsMenuDropdownWindow(dpy, dropdown, 1, 22) == NO,
           "empty 1px panel is not a dropdown");
      PASS(EauIsMenuDropdownWindow(dpy, searchPanel, 22, 22) == NO,
           "search panel at scale 1.0 is not a dropdown");
      PASS(EauIsMenuDropdownWindow(dpy, searchPanel, 25, 25) == NO,
           "search panel at scale 1.1 is not a dropdown");

      /* --- panels a menu item opens are not dropdowns --- */
      PASS(EauIsMenuDropdownWindow(dpy, titledPanel, 340, 22) == NO,
           "titled panel opened from a menu extra is not a dropdown");
      PASS(EauIsMenuDropdownWindow(dpy, unknown, 340, 22) == NO,
           "window without GNUstep style attributes is not a dropdown");

      /* --- other applications' windows are never touched --- */
      PASS(EauIsMenuDropdownWindow(dpy, otherApp, 135, 22) == NO,
           "another application's window is not a Menu dropdown");

      XDestroyWindow(dpy, bar);
      XDestroyWindow(dpy, dropdown);
      XDestroyWindow(dpy, typedDropdown);
      XDestroyWindow(dpy, searchPanel);
      XDestroyWindow(dpy, otherApp);
      XDestroyWindow(dpy, titledPanel);
      XDestroyWindow(dpy, unknown);
      XCloseDisplay(dpy);
    }
  return 0;
}
