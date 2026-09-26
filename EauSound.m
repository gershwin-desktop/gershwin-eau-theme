/*
 * EauSound.m
 * Eau Theme - thin forward to GershwinBehaviors' sound playback
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauSound.h"

#import <dlfcn.h>

/* GershwinBehaviors.bundle exports GBPlaySystemSound as a plain C symbol.
 * Eau does not link the bundle (it is loaded dynamically, see
 * EauEnsureBehaviorsLoaded in Eau+Behaviors.m, which runs before any theme
 * drawing code can call this), so the symbol is looked up in the running
 * process instead of declared in a header we would have to import from the
 * bundle. This keeps Eau building even when Behaviors is missing: the call
 * then just fails silently and the caller falls back to a plain beep. */
BOOL EauPlaySystemSound(NSString *soundName)
{
  static BOOL (*gbPlaySystemSound)(NSString *) = NULL;
  static BOOL looked = NO;

  if (!looked)
    {
      looked = YES;
      gbPlaySystemSound = (BOOL (*)(NSString *))dlsym(RTLD_DEFAULT, "GBPlaySystemSound");
    }

  return gbPlaySystemSound ? gbPlaySystemSound(soundName) : NO;
}
