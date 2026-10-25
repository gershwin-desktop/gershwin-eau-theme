/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauDecorationScale.h"

/* Defined in Eau.m; the AppearanceMetrics macros read it. */
extern CGFloat GSWScaleFactorValue;

/* The window factor in force (0 = none) and the process-wide value it
 * stands in for, which may be 0 when nothing has read it yet. */
static CGFloat windowFactor = 0;
static CGFloat processValue = 0;

void EauSetDecorationScaleFactor(CGFloat factor)
{
  if (factor > 0)
    {
      if (windowFactor == 0)
        processValue = GSWScaleFactorValue;
      windowFactor = factor;
      GSWScaleFactorValue = factor;
      return;
    }
  if (windowFactor == 0)
    return;
  windowFactor = 0;
  GSWScaleFactorValue = processValue;
}

CGFloat EauDecorationScaleFactor(void)
{
  return windowFactor;
}

void EauDecorationScaleInvalidate(void)
{
  if (windowFactor > 0)
    processValue = 0;
  else
    GSWScaleFactorValue = 0;
}
