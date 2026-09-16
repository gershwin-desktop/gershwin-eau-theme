/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* One EauTest window: a tab view with one pane per group of Eau-drawn
 * controls plus a dialog-style Cancel/OK button row.  The "Text" pane is
 * selected first and its text field is the initial first responder, so UI
 * tests can type and use cut/copy/paste right after launch. */
@interface EauTestWindowController : NSObject

- (void)showWindow;

@end
