/* GBThemeHooks+Sheet.h - optional theme hooks used by window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

/* Called through GBThemeIfResponds(): a theme implements only what it wants
 * to style; without them sheets appear instantly with a plain 1px edge. */
@interface GSTheme (GBThemeHooksSheet)

/* Seconds the sheet takes to slide out from under the parent's titlebar.
 * Return 0 to show it at once. */
- (NSTimeInterval)sheetAnimationDurationForWindow:(NSWindow *)sheet;

/* Draw the sheet edge (border, shadow cast by the parent's titlebar, ...)
 * into the sheet's outermost view.  bounds is that view's bounds; the
 * window background is already painted, the sheet content is drawn after. */
- (void)drawSheetBorderInRect:(NSRect)bounds forWindow:(NSWindow *)sheet;

/* The sheet has its own style mask back and is an ordinary window again,
 * not yet shown on its own.  Anything the theme adds to a window when it is
 * first shown (a resize grip, ...) is added to a window that has already
 * been on screen from now on, so the theme may have to set it up here. */
- (void)sheetDidEndForWindow:(NSWindow *)sheet;

@end
