/* GBBehaviors.h - principal class of GershwinBehaviors.bundle
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* The behaviors live in +load of the bundle's categories, so they are
 * installed as soon as the bundle is loaded.  This class only marks the
 * bundle as present: a theme checks NSClassFromString(@"GBBehaviors") to
 * find out whether it still has to load the bundle itself. */
@interface GBBehaviors : NSObject
@end
