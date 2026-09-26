/* GBBehaviors.m - principal class of GershwinBehaviors.bundle
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBBehaviors.h"

@implementation GBBehaviors

/* NSApplication instantiates the principal class of every
 * GSAppKitUserBundles entry; nothing needs to happen here because the
 * categories already installed themselves in +load. */
- (id)init
{
  if ((self = [super init]) != nil)
    {
      NSDebugLog(@"GershwinBehaviors: loaded");
    }
  return self;
}

@end
