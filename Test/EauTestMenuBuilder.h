/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* Builds the standard application main menu (application, File, Edit, Format,
 * Window, Help) so UI tests can drive the usual entries - including the
 * Command-key equivalents - through the Eau menu path. */
@interface EauTestMenuBuilder : NSObject

+ (NSMenu *)mainMenuForApplicationName:(NSString *)appName;

@end
