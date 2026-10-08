/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The "super duper show-it-all": one window with a sidebar listing every
 * Eau control family (from EauShowcaseSectionRegistry) and a content pane
 * per family showing that control's enabled/disabled/selected/key states,
 * plus a Metrics section and a "Compare with metrics" toggle that scans
 * whichever pane is showing with EauMetricsChecker and highlights any
 * control whose frame violates an AppearanceMetrics rule. */

#import <AppKit/AppKit.h>

@interface EauShowcaseWindowController : NSObject

- (void)showWindow;

@end
