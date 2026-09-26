/* GBX11WindowRole.h - the ICCCM WM_WINDOW_ROLE the Gershwin WM attaches by
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <X11/Xlib.h>

/* The window manager hangs a window with role "sheet" from its parent's
 * titlebar and one with role "drawer" from its parent's edge; the parent is
 * WM_TRANSIENT_FOR.  Compare against these by pointer. */
extern NSString *const GBWindowRoleSheet;
extern NSString *const GBWindowRoleDrawer;

/* Writes role; must happen before the window is mapped. */
void GBX11SetAttachedRole(Display *dpy, Window xwin, NSString *role);

/* Removes WM_WINDOW_ROLE only when it is one of ours: any other value was
 * set by the app and stays. */
void GBX11ClearAttachedRole(Display *dpy, Window xwin);
