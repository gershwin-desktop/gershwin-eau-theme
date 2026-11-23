/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* The color a bezel gets while the pointer is over its button: the same hue,
 * slightly brighter.  nil stays nil. */
NSColor *EauHoverColor(NSColor *color);

/* YES when the pointer is inside the button's bezel frame (in the view's
 * coordinates) and the window is on screen. */
BOOL EauPointerIsInside(NSView *view, NSRect frame);

/* Makes the view redraw when the pointer enters or leaves it.  AppKit sends
 * no redraw for that, and the bezel is drawn from the pointer position, so
 * without this the old look stays until something else repaints.  Safe to
 * call on every draw; the area is installed once per view. */
void EauTrackPointerForView(NSView *view);
