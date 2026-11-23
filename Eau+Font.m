/* Eau+Font.m - Eau's UI typography, asked for by Behaviors/NSFont+GB.m
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "Behaviors/GBThemeHooks+Font.h"
#import "Eau.h"

/* These are methods on the theme object, so they only answer while Eau is the
 * theme in charge: another theme keeps the sizes and weights it asks for
 * without an EauThemeIsActive() check. */
@implementation Eau (Font)

- (CGFloat) gbMenuFontSize
{
  return 14.0;
}

/* Weight 6 is the platform's regular UI face (Inter-Medium on Gershwin,
 * matching what a correct GNUstep resolves), not 5 (Inter-Regular). */
- (NSInteger) gbSystemFontWeight: (BOOL)bold
{
  return bold ? 9 : 6;
}

@end
