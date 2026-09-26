/* Eau+Alert.m - alert hooks the behavior bundle asks the theme for
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "Behaviors/GBThemeHooks+Alert.h"
#import "Eau.h"
#import "NSAlert+Eau.h"

@implementation Eau (Alert)

/* EauAlertPanel sizes, centers, raises and focuses itself in its own
 * -runModal, so NSAlert+GB must run it through that instead of a bare
 * runModalForWindow:. */
- (BOOL)runModalForAlertPanel:(NSWindow *)panel result:(NSInteger *)result
{
  if (![panel isKindOfClass:[EauAlertPanel class]])
    return NO;

  NSInteger code = [(EauAlertPanel *)panel runModal];
  if (result != NULL)
    *result = code;
  return YES;
}

@end
