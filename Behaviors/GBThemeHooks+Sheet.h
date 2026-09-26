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

@end
