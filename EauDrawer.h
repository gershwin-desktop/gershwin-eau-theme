/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* NSDrawer under Eau.  libs-gui shows a drawer as a borderless
 * GSDrawerWindow that it moves after its parent from a timer and slides by
 * resizing it in blocking steps; the Gershwin window manager attaches it to
 * the parent instead (see the README), and the theme gives it its place,
 * its look and its outline. */

/* YES for the window libs-gui shows an NSDrawer in. */
BOOL EauIsDrawerWindow(NSWindow *window);

/* The edge of its parent a drawer's window comes out of. */
NSRectEdge EauDrawerEdgeOfWindow(NSWindow *window);

/* Draws the drawer's surface (called from -drawWindowBackground:view:):
 * NO, drawing nothing, when the view is not in a drawer's window. */
BOOL EauDrawDrawerBackground(NSView *view, NSRect rect);
