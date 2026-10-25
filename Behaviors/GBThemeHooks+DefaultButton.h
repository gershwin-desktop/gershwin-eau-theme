/* GBThemeHooks+DefaultButton.h - optional theme hooks for default buttons
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBDefaultButtonHooks)

/* Sent after -[NSWindow setDefaultButtonCell:] has run (cell nil when the
 * window lost its default button), inside the bundle's re-entrancy guard.
 * libs-gui's own -didSetDefaultButtonCell: does not say which window the cell
 * belongs to, and -[NSButtonCell controlView] is nil until the first draw, so
 * a theme that animates the default button per window needs this one. */
- (void) gbDefaultButtonCellChanged: (NSButtonCell *)cell forWindow: (NSWindow *)window;

@end
