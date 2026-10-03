/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* One drawing engine, two jobs: the Metrics section uses it to paint the
 * documentation-style translucent bands (margins, gaps, baseline offsets)
 * with their pixel values, and every other section's "Compare with
 * metrics" toggle uses it to highlight whichever control EauMetricsChecker
 * found a violation for.  Both are just "translucent rect + label", so one
 * class draws both instead of two near-identical drawRect: methods. */

#import <AppKit/AppKit.h>

@interface EauShowcaseMetricsAnnotation : NSObject

@property (nonatomic, readonly) NSRect rect;
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, strong) NSColor *color;

+ (instancetype)annotationWithRect: (NSRect)rect
                              label: (NSString *)label
                              color: (NSColor *)color;

@end

/* A purely decorative overlay: -hitTest: always returns nil so it never
 * intercepts a click meant for the control underneath it (needed both for
 * a person exploring the showcase and for DriveUI driving it). */
@interface EauShowcaseMetricsOverlayView : NSView

@property (nonatomic, copy) NSArray *annotations;

@end
