/* GBMenuTracking.h - state of the menu tracking loop (NSMenu+GB.m)
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* For code inside this bundle. */
NSMenuView *GBGetTrackedMenuView(void);
BOOL GBGetKeyboardNavActive(void);
void GBSetKeyboardNavActive(BOOL active);

/* A class rather than only C functions so a theme can ask without linking
 * against the bundle: NSClassFromString(@"GBMenuTracking") is Nil when the
 * bundle is absent, and the theme then treats the menu as not tracking. */
@interface GBMenuTracking : NSObject
/* YES while -[NSMenuView trackWithEvent:] is running (mouse or keyboard). */
+ (BOOL)isTracking;
/* The outermost menu view being tracked, or nil. */
+ (NSMenuView *)trackedMenuView;
@end
