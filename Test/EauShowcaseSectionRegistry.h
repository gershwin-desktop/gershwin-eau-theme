/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The showcase's single source of truth for "which sections exist, in
 * which order": the sidebar list is built from it, and a DriveUI script
 * walks the same list to prove every section is reachable.  Kept
 * Foundation-only and separate from EauShowcaseWindowController so the
 * ordering/uniqueness rules can be proven headless. */

#import <Foundation/Foundation.h>

@interface EauShowcaseSection : NSObject

@property (nonatomic, readonly, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *title;

/* The selector on EauShowcaseWindowController that builds this section's
 * content view; kept here rather than hardcoded in the controller so a
 * new section is one array entry, not a scattered set of switch cases. */
@property (nonatomic, readonly) SEL builderSelector;

+ (instancetype)sectionWithIdentifier: (NSString *)identifier
                                 title: (NSString *)title
                       builderSelector: (SEL)builderSelector;

@end

@interface EauShowcaseSectionRegistry : NSObject

/* Ordered, one entry per control family plus "Metrics" - the order the
 * sidebar lists them in and a DriveUI walk visits them in. */
+ (NSArray *)allSections;

/* nil when no section has that identifier. */
+ (EauShowcaseSection *)sectionWithIdentifier: (NSString *)identifier;

@end
