/* GBThemeHooks+FocusRing.h - optional theme hooks for keyboard focus rings
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBFocusRingHooks)

/* Sent when keyboard focus rings should start or stop showing: they appear
 * once the user navigates with Tab / Shift-Tab and disappear on the next
 * mouse click or scroll (macOS full keyboard access).  window is the window
 * whose event changed the state; when visible is NO the theme should clear
 * any ring it already painted there.  Sent only on a change of state. */
- (void) gbKeyboardFocusVisibilityChanged: (BOOL)visible inWindow: (NSWindow *)window;

@end
