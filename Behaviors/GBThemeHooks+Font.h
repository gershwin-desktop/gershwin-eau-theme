/* GBThemeHooks+Font.h - optional theme hooks for UI font typography
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

@interface GSTheme (GBFontHooks)

/* Point size the theme draws menu and menu bar text at, whatever size the
 * caller asked for; 0 keeps the requested size.  Without the hook (another
 * theme, or no theme loaded yet) the requested size is kept. */
- (CGFloat) gbMenuFontSize;

/* Face weight (NSFontManager scale) to enforce for the system font (bold NO)
 * or the bold system font (bold YES), so a fontconfig mis-resolution cannot
 * swap regular and bold; 0 trusts what fontconfig resolved.  Without the hook
 * nothing is enforced, so another theme gets the faces it would get without
 * this bundle. */
- (NSInteger) gbSystemFontWeight: (BOOL)bold;

@end
