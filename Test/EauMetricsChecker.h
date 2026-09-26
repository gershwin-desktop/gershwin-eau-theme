/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Pure geometry checker for the AppearanceMetrics.h spacing/sizing rules.
 * The showcase's "Compare with metrics" toggle needs to report WHICH rule
 * a control's frame violates, not just that it looks off, so the checker
 * takes plain frames and returns a named violation.  Foundation-only: no
 * AppKit view is touched here, so this is tested headless. */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, EauMetricsEdge)
{
  EauMetricsEdgeLeft,
  EauMetricsEdgeRight,
  EauMetricsEdgeTop,
  EauMetricsEdgeBottom
};

/* One control's geometry as the checker needs it: a frame in its
 * container's (or its row's) coordinate space, and the fixed height
 * AppearanceMetrics requires for its kind - 0 when no fixed-height rule
 * applies (a text view, a box, a tab view's overall frame, ...). */
@interface EauMetricsControl : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) NSRect frame;
@property (nonatomic, readonly) CGFloat requiredHeight;

+ (instancetype)controlWithName: (NSString *)name
                           frame: (NSRect)frame
                  requiredHeight: (CGFloat)requiredHeight;

@end

/* One rule violation: which AppearanceMetrics rule, a human-readable
 * message, and the measured vs. required value (so a caller can also
 * render the numbers next to a highlight). */
@interface EauMetricsViolation : NSObject

@property (nonatomic, readonly, copy) NSString *ruleName;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly) CGFloat measured;
@property (nonatomic, readonly) CGFloat expected;

+ (instancetype)violationWithRuleName: (NSString *)ruleName
                               message: (NSString *)message
                              measured: (CGFloat)measured
                              expected: (CGFloat)expected;

@end

@interface EauMetricsChecker : NSObject

/* "Normal buttons shall always be 20px high ... Small buttons ... 17px",
 * and the matching rules for tabs, text fields, radio/checkboxes: a
 * control with a known fixed height must be exactly that tall.  Returns
 * nil when control.requiredHeight is 0 (no rule for this kind) or the
 * frame already complies. */
+ (EauMetricsViolation *)heightViolationForControl: (EauMetricsControl *)control;

/* "All spacing between dialog elements shall be a multiple of 2px (2, 4,
 * 6, 8, 12, 16, 20, or 24)" (AppearanceMetrics.h): checks the gap between
 * control and one neighbour.  neighborOrNil == nil skips the check
 * (control is alone in its row/column).  verticalLayout selects whether
 * the two sit stacked top-to-bottom (checks the vertical gap) or side by
 * side (checks the horizontal gap).  The two frames may be given in
 * either order.  A negative gap (the frames overlap) is always reported. */
+ (EauMetricsViolation *)spacingViolationForControl: (EauMetricsControl *)control
                                            neighbor: (EauMetricsControl *)neighborOrNil
                                      verticalLayout: (BOOL)verticalLayout;

/* Content margin from a container's edge (METRICS_CONTENT_SIDE_MARGIN /
 * TOP / BOTTOM_MARGIN, or a group box's 16px inset).  Returns nil when
 * the control's near edge sits exactly requiredMargin from
 * containerBounds' matching edge. */
+ (EauMetricsViolation *)marginViolationForControl: (EauMetricsControl *)control
                                    containerBounds: (NSRect)containerBounds
                                               edge: (EauMetricsEdge)edge
                                     requiredMargin: (CGFloat)requiredMargin;

@end
