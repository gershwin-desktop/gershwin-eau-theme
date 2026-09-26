/* GBThemeHooks+Window.h - optional theme hooks for window presentation
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBWindowHooks)

/* Sent right before -orderFront:, -orderFrontRegardless and
 * -makeKeyAndOrderFront: bring a window on screen, so the theme can add
 * decorations (such as a grow box) that must be there on the first frame. */
- (void) gbWindowWillOrderFront: (NSWindow *)window;

@end
