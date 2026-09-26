/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* Whether Eau is the theme in charge right now.  Every swizzle in this bundle
 * asks before doing anything Eau-specific, so the flag lives in a file of its
 * own: the ObjectTesting tools under Tests/ link those category files one at
 * a time, without the theme class that sets it. */

#import <Foundation/Foundation.h>

#import "Eau.h"

static BOOL gEauThemeActive = NO;

BOOL EauThemeIsActive(void)
{
  return gEauThemeActive;
}

void EauSetThemeActive(BOOL flag)
{
  gEauThemeActive = flag;
}
