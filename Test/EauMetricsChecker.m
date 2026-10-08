/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauMetricsChecker.h"

/* AppearanceMetrics.h: "All spacing between dialog elements shall be a
 * multiple of 2px (2, 4, 6, 8, 12, 16, 20, or 24)".  The set is a fixed
 * whitelist, not "any multiple of 2" - 10/14/18/22 are deliberately not
 * members (see the gershwin-appearance-metrics skill's wrong/right table). */
static const CGFloat kCanonicalSpacing[] = { 2, 4, 6, 8, 12, 16, 20, 24 };
static const NSUInteger kCanonicalSpacingCount =
  sizeof(kCanonicalSpacing) / sizeof(kCanonicalSpacing[0]);

static BOOL isCanonicalSpacing(CGFloat gap)
{
  NSUInteger i;
  for (i = 0; i < kCanonicalSpacingCount; i++)
    {
      if (fabs(gap - kCanonicalSpacing[i]) < 0.5)
        return YES;
    }
  return NO;
}

@implementation EauMetricsControl

+ (instancetype)controlWithName: (NSString *)name
                           frame: (NSRect)frame
                  requiredHeight: (CGFloat)requiredHeight
{
  EauMetricsControl *control = [[self alloc] init];
  control->_name = [name copy];
  control->_frame = frame;
  control->_requiredHeight = requiredHeight;
  return control;
}

@end

@implementation EauMetricsViolation

+ (instancetype)violationWithRuleName: (NSString *)ruleName
                               message: (NSString *)message
                              measured: (CGFloat)measured
                              expected: (CGFloat)expected
{
  EauMetricsViolation *violation = [[self alloc] init];
  violation->_ruleName = [ruleName copy];
  violation->_message = [message copy];
  violation->_measured = measured;
  violation->_expected = expected;
  return violation;
}

@end

@implementation EauMetricsChecker

+ (EauMetricsViolation *)heightViolationForControl: (EauMetricsControl *)control
{
  CGFloat height;

  if ([control requiredHeight] <= 0)
    return nil;

  height = NSHeight([control frame]);
  if (fabs(height - [control requiredHeight]) < 0.5)
    return nil;

  return [EauMetricsViolation
    violationWithRuleName: @"METRICS_*_HEIGHT"
                   message: [NSString stringWithFormat:
                     @"%@ is %.1fpx tall, AppearanceMetrics requires %.1fpx",
                     [control name], height, [control requiredHeight]]
                  measured: height
                  expected: [control requiredHeight]];
}

+ (EauMetricsViolation *)spacingViolationForControl: (EauMetricsControl *)control
                                            neighbor: (EauMetricsControl *)neighborOrNil
                                      verticalLayout: (BOOL)verticalLayout
{
  NSRect a;
  NSRect b;
  CGFloat gap;

  if (neighborOrNil == nil)
    return nil;

  a = [control frame];
  b = [neighborOrNil frame];

  /* The gap between two intervals, independent of which frame was passed
   * first: positive when they do not touch, <= 0 when they overlap. */
  if (verticalLayout)
    gap = MAX(NSMinY(a), NSMinY(b)) - MIN(NSMaxY(a), NSMaxY(b));
  else
    gap = MAX(NSMinX(a), NSMinX(b)) - MIN(NSMaxX(a), NSMaxX(b));

  if (gap < 0)
    return [EauMetricsViolation
      violationWithRuleName: @"no control overlap"
                     message: [NSString stringWithFormat:
                       @"%@ and %@ overlap by %.1fpx",
                       [control name], [neighborOrNil name], -gap]
                    measured: gap
                    expected: 0];

  if (!isCanonicalSpacing(gap))
    return [EauMetricsViolation
      violationWithRuleName: @"METRICS_SPACE_* (2/4/6/8/12/16/20/24)"
                     message: [NSString stringWithFormat:
                       @"gap between %@ and %@ is %.1fpx, AppearanceMetrics "
                       @"requires a multiple of 2px from {2,4,6,8,12,16,20,24}",
                       [control name], [neighborOrNil name], gap]
                    measured: gap
                    expected: 0];

  return nil;
}

+ (EauMetricsViolation *)marginViolationForControl: (EauMetricsControl *)control
                                    containerBounds: (NSRect)containerBounds
                                               edge: (EauMetricsEdge)edge
                                     requiredMargin: (CGFloat)requiredMargin
{
  NSRect frame = [control frame];
  CGFloat measured;
  NSString *edgeName;

  switch (edge)
    {
      case EauMetricsEdgeLeft:
        measured = NSMinX(frame) - NSMinX(containerBounds);
        edgeName = @"left";
        break;
      case EauMetricsEdgeRight:
        measured = NSMaxX(containerBounds) - NSMaxX(frame);
        edgeName = @"right";
        break;
      case EauMetricsEdgeTop:
        measured = NSMaxY(containerBounds) - NSMaxY(frame);
        edgeName = @"top";
        break;
      case EauMetricsEdgeBottom:
      default:
        measured = NSMinY(frame) - NSMinY(containerBounds);
        edgeName = @"bottom";
        break;
    }

  if (fabs(measured - requiredMargin) < 0.5)
    return nil;

  return [EauMetricsViolation
    violationWithRuleName: @"METRICS_CONTENT_*_MARGIN"
                   message: [NSString stringWithFormat:
                     @"%@ is %.1fpx from the %@ edge, AppearanceMetrics requires %.1fpx",
                     [control name], measured, edgeName, requiredMargin]
                  measured: measured
                  expected: requiredMargin];
}

@end
