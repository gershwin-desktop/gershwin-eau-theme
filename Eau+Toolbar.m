/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Eau+Toolbar.m - a window's toolbar has the window's own background.
 * GSTheme's default toolbar background is clear, which let the white
 * behind the toolbar show through, so a toolbar looked like part of the
 * content area rather than of the window. */

#import "Eau.h"

@implementation Eau (EauToolbar)

- (NSColor *) toolbarBackgroundColor
{
  return [NSColor windowBackgroundColor];
}

@end
