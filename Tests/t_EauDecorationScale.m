/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_EauDecorationScale.m - the window manager draws one window's title bar
 * at the factor of that window's monitor; the AppearanceMetrics macros must
 * see that factor while it is set and the process-wide one afterwards, and a
 * live GSScaleFactor change must not be lost or leak into a window's factor.
 * Headless, Foundation only.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "AppearanceMetrics.h"
#import "EauDecorationScale.h"

/* Defined in Eau.m inside the theme; this tool does not link the theme. */
CGFloat GSWScaleFactorValue = 0;

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("decoration scale factor")
    GSWScaleFactorValue = 1.0;
    PASS(EauDecorationScaleFactor() == 0, "no window factor at first");

    EauSetDecorationScaleFactor(2.0);
    PASS(GSWScaleFactor() == 2.0, "the metrics see the window's factor");
    PASS(METRICS_TITLEBAR_HEIGHT_PX == METRICS_TITLEBAR_HEIGHT * 2.0,
         "the title bar height follows it");
    PASS(EauDecorationScaleFactor() == 2.0, "the window factor is reported");

    EauSetDecorationScaleFactor(1.5);
    PASS(GSWScaleFactor() == 1.5, "another window's factor replaces it");

    EauSetDecorationScaleFactor(0);
    PASS(GSWScaleFactor() == 1.0, "the process-wide factor comes back");
    PASS(EauDecorationScaleFactor() == 0, "and no window factor is reported");

    EauSetDecorationScaleFactor(0);
    PASS(GSWScaleFactor() == 1.0, "ending twice changes nothing");

    GSWScaleFactorValue = 0;
    EauSetDecorationScaleFactor(2.0);
    EauSetDecorationScaleFactor(0);
    PASS(GSWScaleFactorValue == 0, "an unread process-wide factor stays unread");

    GSWScaleFactorValue = 1.0;
    EauSetDecorationScaleFactor(2.0);
    EauDecorationScaleInvalidate();
    PASS(GSWScaleFactor() == 2.0, "invalidating keeps the window's factor");
    EauSetDecorationScaleFactor(0);
    PASS(GSWScaleFactorValue == 0, "but the process-wide one is read again");

    GSWScaleFactorValue = 1.25;
    EauDecorationScaleInvalidate();
    PASS(GSWScaleFactorValue == 0, "invalidating without a window factor clears the cache");
  END_SET("decoration scale factor")

  [arp release];
  return 0;
}
