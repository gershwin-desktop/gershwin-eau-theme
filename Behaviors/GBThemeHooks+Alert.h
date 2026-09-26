/* GBThemeHooks+Alert.h - optional theme hooks used by NSAlert+GB.m
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBTheme.h"

@interface GSTheme (GBAlertHooks)

/* A theme that builds its own alert panel class knows how to run it (size,
 * position, level, default-button focus).  Return NO when `panel` is not one
 * of the theme's panels so the behavior falls back to runModalForWindow:. */
- (BOOL)runModalForAlertPanel:(NSWindow *)panel result:(NSInteger *)result;

/* Lay the panel out for good before it is first shown.  Resizing or moving
 * a panel that is already on screen leaves its pre-layout picture behind on
 * the composited screen (a ghost in the corner), because the area it
 * vacates is never damaged.  Without the hook the panel is only centered. */
- (void)prepareAlertPanelForDisplay:(NSWindow *)panel;

@end
