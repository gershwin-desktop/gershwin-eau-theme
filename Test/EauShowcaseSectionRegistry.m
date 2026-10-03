/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauShowcaseSectionRegistry.h"

@implementation EauShowcaseSection

+ (instancetype)sectionWithIdentifier: (NSString *)identifier
                                 title: (NSString *)title
                       builderSelector: (SEL)builderSelector
{
  EauShowcaseSection *section = [[self alloc] init];
  section->_identifier = [identifier copy];
  section->_title = [title copy];
  section->_builderSelector = builderSelector;
  return section;
}

@end

/* NSSelectorFromString rather than @selector(): the registry is a pure
 * Foundation unit and must not need to import (or link) the AppKit-based
 * window controller just to name its builder methods. */
@implementation EauShowcaseSectionRegistry

+ (NSArray *)allSections
{
  static NSArray *sections = nil;

  if (sections == nil)
    {
      sections = @[
        [EauShowcaseSection sectionWithIdentifier: @"buttons" title: @"Buttons"
                                   builderSelector: NSSelectorFromString(@"buildButtonsSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"checksRadios" title: @"Checkboxes & Radios"
                                   builderSelector: NSSelectorFromString(@"buildChecksRadiosSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"popUpsCombos" title: @"Pop-Ups & Combo Boxes"
                                   builderSelector: NSSelectorFromString(@"buildPopUpsCombosSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"textSearch" title: @"Text & Search Fields"
                                   builderSelector: NSSelectorFromString(@"buildTextSearchSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"slidersSteppers" title: @"Sliders & Steppers"
                                   builderSelector: NSSelectorFromString(@"buildSlidersSteppersSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"progressLevel" title: @"Progress & Level Indicators"
                                   builderSelector: NSSelectorFromString(@"buildProgressLevelSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"segmentedTabs" title: @"Segmented & Tab Views"
                                   builderSelector: NSSelectorFromString(@"buildSegmentedTabsSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"boxesGroups" title: @"Boxes"
                                   builderSelector: NSSelectorFromString(@"buildBoxesGroupsSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"tablesOutlines" title: @"Tables & Outline Views"
                                   builderSelector: NSSelectorFromString(@"buildTablesOutlinesSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"browsers" title: @"Browsers"
                                   builderSelector: NSSelectorFromString(@"buildBrowsersSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"scrollSplit" title: @"Scroll & Split Views"
                                   builderSelector: NSSelectorFromString(@"buildScrollSplitSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"disclosureToolbars" title: @"Disclosure & Tool Bars"
                                   builderSelector: NSSelectorFromString(@"buildDisclosureToolbarsSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"sheetsAlerts" title: @"Sheets & Alerts"
                                   builderSelector: NSSelectorFromString(@"buildSheetsAlertsSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"drawers" title: @"Drawers"
                                   builderSelector: NSSelectorFromString(@"buildDrawersSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"colorDate" title: @"Colour Wells & Date Pickers"
                                   builderSelector: NSSelectorFromString(@"buildColorDateSection:")],
        [EauShowcaseSection sectionWithIdentifier: @"metrics" title: @"Metrics"
                                   builderSelector: NSSelectorFromString(@"buildMetricsSection:")],
      ];
    }
  return sections;
}

+ (EauShowcaseSection *)sectionWithIdentifier: (NSString *)identifier
{
  for (EauShowcaseSection *section in [self allSections])
    {
      if ([[section identifier] isEqualToString: identifier])
        return section;
    }
  return nil;
}

@end
