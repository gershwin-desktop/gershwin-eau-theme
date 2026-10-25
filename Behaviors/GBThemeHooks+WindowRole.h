/* GBThemeHooks+WindowRole.h - optional theme hooks for window-manager roles
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBThemeHooksWindowRole)

/* The WM_WINDOW_ROLE a window gets on every order-in when it is not a
 * sheet: currently only GBWindowRoleDrawer's value "drawer" is honoured,
 * for the drawer windows the theme places itself.  nil for none. */
- (NSString *)windowManagerRoleForWindow:(NSWindow *)window;

/* Outline the WM cuts a window with a role to (_WM_SHAPE_PATH), as int32
 * items in the WM's path format; nil keeps the rectangle. */
- (NSData *)windowManagerShapePathForWindow:(NSWindow *)window;

@end
