/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

/* Stacks labelled rows of controls from the top of a view downwards, so the
 * EauTest panes share one set of AppearanceMetrics spacing rules instead of
 * each hand-computing y-up frames. */
@interface EauTestFormBuilder : NSObject

- (instancetype)initWithView:(NSView *)view;

/* Places the controls left to right after a right-aligned label.  Each control
 * keeps its own width; its height is used as is.  The row is as tall as its
 * tallest control. */
- (void)addRowWithLabel:(NSString *)label controls:(NSArray *)controls;

@end
