/* Eau+WindowRole.m - tells the window manager which windows are drawers
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Implements the optional hooks of Behaviors/GBThemeHooks+WindowRole.h;
 * GershwinBehaviors writes WM_WINDOW_ROLE and _WM_SHAPE_PATH on order-in.
 * Only Eau places drawers itself (EauDrawer.m), so only under Eau may the
 * window manager attach them - otherwise libs-gui's follow timer and the
 * window manager would both move the drawer.
 */

#import <AppKit/AppKit.h>

#import "AppearanceMetrics.h"
#import "Behaviors/GBThemeHooks+WindowRole.h"
#import "Eau.h"
#import "EauDrawer.h"
#import "EauDrawerGeometry.h"

@implementation Eau (WindowRole)

- (NSString *)windowManagerRoleForWindow:(NSWindow *)window
{
  return EauIsDrawerWindow(window) ? @"drawer" : nil;
}

/* The drawer's two outer corners are rounded; the window manager cuts the
 * outline with a smooth edge and bends the shadow along. */
- (NSData *)windowManagerShapePathForWindow:(NSWindow *)window
{
  if (!EauIsDrawerWindow(window)) {
    return nil;
  }
  return [EauDrawerGeometry shapePathForEdge:EauDrawerEdgeOfWindow(window)
                                      radius:METRICS_DRAWER_CORNER_RADIUS_PX];
}

@end
