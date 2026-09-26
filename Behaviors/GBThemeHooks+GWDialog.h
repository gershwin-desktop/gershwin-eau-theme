/* GBThemeHooks+GWDialog.h - optional theme hooks for Workspace's GWDialog
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBGWDialogHooks)

/* Sent from -[GWDialog initWithTitle:editText:switchTitle:] once the dialog
 * is built and before the bundle wires up its keyboard (Return, Escape, Tab
 * loop, initial first responder), so the theme can restyle, resize and
 * position the dialog.  Without it the dialog keeps Workspace's own layout. */
- (void) gbLayoutGWDialog: (NSWindow *)dialog;

@end
