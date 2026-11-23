/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The window manager draws the title bars of windows on monitors with
 * different scale factors in one process.  The AppearanceMetrics macros all
 * read one process-wide factor (GSWScaleFactorValue), so for the length of
 * one window's drawing the factor of that window's monitor stands in for it
 * and the process-wide value comes back afterwards. */

#import <Foundation/Foundation.h>

/* Draw at `factor` from now on; 0 (or less) ends that and restores the
 * process-wide factor.  Setting another factor while one is in force
 * replaces it and still restores the original value at the end. */
void EauSetDecorationScaleFactor(CGFloat factor);

/* The factor set with EauSetDecorationScaleFactor(), 0 when none is. */
CGFloat EauDecorationScaleFactor(void);

/* The process-wide factor changed (GSScaleFactor default): forget the cached
 * value without disturbing a window's factor that is in force. */
void EauDecorationScaleInvalidate(void);
