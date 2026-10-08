/* GBTheme.h - how behaviors ask the active theme for visuals
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <GNUstepGUI/GSTheme.h>

/* Behaviors decide what happens and when; the theme decides how it looks.
 * Hooks are optional GSTheme methods: a behavior calls one only when the
 * active theme implements it and otherwise falls back to a plain default,
 * so the bundle works under themes that know nothing about it. */
static inline id GBThemeIfResponds(SEL sel)
{
  GSTheme *theme = [GSTheme theme];
  return [theme respondsToSelector:sel] ? theme : nil;
}
