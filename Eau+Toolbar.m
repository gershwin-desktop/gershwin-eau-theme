/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Eau+Toolbar.m - a window's toolbar continues its title bar: the toolbar
 * is filled with the colour the title bar gradient ends in, the active or
 * the inactive one like the title bar above it, instead of GSTheme's clear
 * background that let the white content area show through. */

#import "Eau.h"

@implementation Eau (EauToolbar)

- (NSColor *) toolbarBackgroundColor
{
  /* GSToolbarView asks while it draws, so the view in focus tells which
   * window the bar belongs to.  Asked outside drawing (whether the bar is
   * opaque), both colours give the same answer. */
  NSWindow *window = [[NSView focusView] window];

  return [self windowTitlebarBottomColorActive: (window == nil || [window isKeyWindow])];
}

@end
