/* t_EauShowcaseSectionRegistry.m - ObjectTesting coverage for the showcase's
 * section list: the single source of truth the sidebar and a DriveUI walk
 * both read from.  Headless.
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../Test/EauShowcaseSectionRegistry.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  NSArray *sections = [EauShowcaseSectionRegistry allSections];

  PASS([sections count] >= 15,
    "the registry lists one section per control family plus Metrics (>= 15)");

  /* Every control family the brief named must have a section: no family
   * silently dropped from the showcase. */
  NSArray *mustExist = @[ @"buttons", @"checksRadios", @"popUpsCombos",
    @"textSearch", @"slidersSteppers", @"progressLevel", @"segmentedTabs",
    @"boxesGroups", @"tablesOutlines", @"browsers", @"scrollSplit",
    @"disclosureToolbars", @"sheetsAlerts", @"drawers", @"colorDate",
    @"metrics" ];
  for (NSString *identifier in mustExist)
    {
      PASS([EauShowcaseSectionRegistry sectionWithIdentifier: identifier] != nil,
        "the registry has a section for every required control family");
    }

  PASS([EauShowcaseSectionRegistry sectionWithIdentifier: @"doesNotExist"] == nil,
    "an unknown identifier resolves to nil, not a crash or a wrong section");

  /* No duplicate identifiers - a duplicate would make two sidebar rows
   * select the same content and the DriveUI walk under-count sections. */
  NSMutableSet *seen = [NSMutableSet set];
  BOOL sawDuplicate = NO;
  for (EauShowcaseSection *section in sections)
    {
      if ([seen containsObject: [section identifier]])
        sawDuplicate = YES;
      [seen addObject: [section identifier]];
    }
  PASS(sawDuplicate == NO, "no two sections share an identifier");

  /* Every section must name a builder selector - an empty one means a
   * sidebar row that shows a blank pane with no way to notice it. */
  BOOL allHaveBuilders = YES;
  for (EauShowcaseSection *section in sections)
    {
      if ([section builderSelector] == NULL || [section builderSelector] == 0)
        allHaveBuilders = NO;
    }
  PASS(allHaveBuilders, "every section names a non-null builder selector");

  /* The Metrics section (the "show the rules visibly" section) must be
   * present and last, so the ruler/overlay reference is easy to find. */
  EauShowcaseSection *last = [sections lastObject];
  PASS_EQUAL([last identifier], @"metrics", "Metrics is the final section in the sidebar order");

  [arp release];
  return 0;
}
