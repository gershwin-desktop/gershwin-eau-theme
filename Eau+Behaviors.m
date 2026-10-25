/* Eau+Behaviors.m - make sure GershwinBehaviors.bundle is loaded
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "Eau.h"

/* Behavior (keyboard, menus, modality) lives in GershwinBehaviors.bundle so
 * it survives a theme switch.  libs-gui normally loads it through the
 * GSAppKitUserBundles default; when that default is missing the desktop
 * would silently lose all of it, so the theme loads the bundle itself. */
void EauEnsureBehaviorsLoaded(void)
{
  if (NSClassFromString(@"GBBehaviors") != Nil)
    return;

  NSArray *libraries =
    NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSAllDomainsMask, YES);
  for (NSString *library in libraries)
    {
      NSString *path = [[library stringByAppendingPathComponent:@"Bundles"]
        stringByAppendingPathComponent:@"GershwinBehaviors.bundle"];
      NSBundle *bundle = [NSBundle bundleWithPath:path];
      if (bundle != nil && [bundle load])
        {
          NSWarnMLog(@"GershwinBehaviors.bundle was not in GSAppKitUserBundles; "
                     @"loaded it from %@", path);
          (void)[[[bundle principalClass] alloc] init];
          return;
        }
    }
  NSWarnMLog(@"GershwinBehaviors.bundle not found - desktop behaviors are missing");
}
