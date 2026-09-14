/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef EauMenuWindowFilter_h
#define EauMenuWindowFilter_h

#import <Foundation/Foundation.h>
#import <X11/Xlib.h>

/* Height in device pixels up to which a Menu.app window is a utility window
   (search panel, caches) rather than a dropdown.  GNUstep scales window
   sizes by the user space scale factor, so a fixed pixel limit stops
   covering these windows as soon as the factor is not 1.0. */
int EauMenuUtilityHeightLimit(CGFloat menuBarHeight, CGFloat scaleFactor);

/* YES if the top-level X window w is one of Menu.app's dropdown panels, i.e.
   a window the stale-panel cleanup may withdraw or destroy.  height is the
   window's current height in device pixels. */
BOOL EauIsMenuDropdownWindow(Display *dpy, Window w, int height,
                             int utilityHeightLimit);

#endif
