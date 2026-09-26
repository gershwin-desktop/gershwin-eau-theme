/*
 * EauSound.h
 * Eau Theme - thin forward to GershwinBehaviors' sound playback
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* The real implementation (WAV decode/attenuate, alert-volume lookup) moved
 * to Behaviors/GBSound.{h,m} as GBPlaySystemSound: it is theme-independent
 * and still wanted under any theme. Drawing-side code in Eau (e.g. the
 * progress indicator's completion sound) keeps calling this name; see
 * EauSound.m for how it reaches the bundle. */
BOOL EauPlaySystemSound(NSString *soundName);
