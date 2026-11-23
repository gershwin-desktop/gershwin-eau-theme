/* GBBehaviors.h - principal class of GershwinBehaviors.bundle
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class NSWindow;

/* The behaviors live in +load of the bundle's categories, so they are
 * installed as soon as the bundle is loaded.  This class only marks the
 * bundle as present: a theme checks NSClassFromString(@"GBBehaviors") to
 * find out whether it still has to load the bundle itself. */
@interface GBBehaviors : NSObject

/* Plays a named system sound at the user's alert volume (see GBSound.h).
 * For themes that trigger a sound from drawing-side code: they reach it
 * through NSClassFromString(@"GBBehaviors") and stay silent without the
 * bundle.  Returns NO when no such sound exists. */
+ (BOOL)playSystemSound:(NSString *)name;

/* YES when a modal session for window started now would show it as a sheet
 * (GBAutoSheet.m).  A theme that shows its alert panel itself before
 * -runModalForWindow: skips that (centering, raising) when this says YES,
 * or the dialog would first flash up in the middle of the screen. */
+ (BOOL)willRunModalWindowAsSheet:(NSWindow *)window;

@end
