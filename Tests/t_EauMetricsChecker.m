/* t_EauMetricsChecker.m - ObjectTesting coverage for the showcase's pure
 * AppearanceMetrics rule checker.  Headless: Foundation-only geometry, no
 * display touched.
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../Test/EauMetricsChecker.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- height rule --- */
  {
    EauMetricsControl *okButton = [EauMetricsControl controlWithName: @"OK"
      frame: NSMakeRect(0, 0, 100, 20) requiredHeight: 20];
    PASS([EauMetricsChecker heightViolationForControl: okButton] == nil,
      "a 20px button reports no height violation");

    EauMetricsControl *tooTall = [EauMetricsControl controlWithName: @"Tall"
      frame: NSMakeRect(0, 0, 100, 24) requiredHeight: 20];
    EauMetricsViolation *v = [EauMetricsChecker heightViolationForControl: tooTall];
    PASS(v != nil, "a 24px button (should be 20px) is flagged");
    PASS(EQ([v measured], 24.0), "violation reports the measured height");
    PASS(EQ([v expected], 20.0), "violation reports the required height");

    EauMetricsControl *noRule = [EauMetricsControl controlWithName: @"Box"
      frame: NSMakeRect(0, 0, 100, 61) requiredHeight: 0];
    PASS([EauMetricsChecker heightViolationForControl: noRule] == nil,
      "requiredHeight 0 means no fixed-height rule applies");
  }

  /* --- spacing rule: canonical set is {2,4,6,8,12,16,20,24}, not every even number --- */
  {
    /* Two rows 16px apart vertically (a real gap AppearanceMetrics allows
     * between primary control groups). */
    EauMetricsControl *upper = [EauMetricsControl controlWithName: @"Row1"
      frame: NSMakeRect(0, 100, 200, 20) requiredHeight: 0];
    EauMetricsControl *lower = [EauMetricsControl controlWithName: @"Row2"
      frame: NSMakeRect(0, 64, 200, 20) requiredHeight: 0]; /* gap = 100-84 = 16 */
    PASS([EauMetricsChecker spacingViolationForControl: lower neighbor: upper
      verticalLayout: YES] == nil, "a 16px vertical gap is canonical");

    /* Same pair, argument order swapped: the rule must not depend on which
     * frame was passed as "control" vs. "neighbor". */
    PASS([EauMetricsChecker spacingViolationForControl: upper neighbor: lower
      verticalLayout: YES] == nil, "the gap check is order independent");

    /* 10px is NOT in the canonical set even though it is even.  offBy sits
     * entirely below upper (upper's bottom edge is at y=100) with a 10px
     * gap: offBy's top edge is at 100-10=90, so its origin is 90-20=70. */
    EauMetricsControl *offBy = [EauMetricsControl controlWithName: @"Row3"
      frame: NSMakeRect(0, 70, 200, 20) requiredHeight: 0]; /* gap = 100-90=10 */
    EauMetricsViolation *badGap = [EauMetricsChecker
      spacingViolationForControl: offBy neighbor: upper verticalLayout: YES];
    PASS(badGap != nil, "a 10px vertical gap is flagged (not in {2,4,6,8,12,16,20,24})");

    /* Overlapping frames. */
    EauMetricsControl *overlap = [EauMetricsControl controlWithName: @"Row4"
      frame: NSMakeRect(0, 95, 200, 20) requiredHeight: 0]; /* overlaps upper by 15 */
    EauMetricsViolation *overlapViolation = [EauMetricsChecker
      spacingViolationForControl: overlap neighbor: upper verticalLayout: YES];
    PASS(overlapViolation != nil, "overlapping frames are flagged");
    PASS([overlapViolation measured] < 0, "an overlap reports a negative gap");

    /* Horizontal gap of 12px (push-button-to-push-button spacing). */
    EauMetricsControl *left = [EauMetricsControl controlWithName: @"Cancel"
      frame: NSMakeRect(0, 0, 100, 20) requiredHeight: 0];
    EauMetricsControl *right = [EauMetricsControl controlWithName: @"OK"
      frame: NSMakeRect(112, 0, 100, 20) requiredHeight: 0]; /* gap = 112-100=12 */
    PASS([EauMetricsChecker spacingViolationForControl: right neighbor: left
      verticalLayout: NO] == nil, "a 12px horizontal gap is canonical");

    PASS([EauMetricsChecker spacingViolationForControl: left neighbor: nil
      verticalLayout: NO] == nil, "a nil neighbor skips the spacing check");
  }

  /* --- margin rule --- */
  {
    NSRect container = NSMakeRect(0, 0, 500, 340);
    EauMetricsControl *field = [EauMetricsControl controlWithName: @"Field"
      frame: NSMakeRect(24, 0, 452, 22) requiredHeight: 0];
    PASS([EauMetricsChecker marginViolationForControl: field containerBounds: container
      edge: EauMetricsEdgeLeft requiredMargin: 24] == nil,
      "a control flush at the 24px side margin reports no violation");

    EauMetricsControl *tooClose = [EauMetricsControl controlWithName: @"Field2"
      frame: NSMakeRect(10, 0, 452, 22) requiredHeight: 0];
    EauMetricsViolation *marginViolation = [EauMetricsChecker
      marginViolationForControl: tooClose containerBounds: container
      edge: EauMetricsEdgeLeft requiredMargin: 24];
    PASS(marginViolation != nil, "a control 10px from the left edge (should be 24px) is flagged");
    PASS(EQ([marginViolation measured], 10.0), "the margin violation reports the measured distance");
  }

  [arp release];
  return 0;
}
