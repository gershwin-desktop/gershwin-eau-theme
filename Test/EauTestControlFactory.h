/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Small control builders shared by every EauTest window: the original
 * form-based test window and the showcase both need "a push button at the
 * metrics-correct size", "a switch", "an input field with a bezel" - kept
 * here once instead of as static helpers copied into each controller. */

#import <AppKit/AppKit.h>

@interface EauTestControlFactory : NSObject

+ (NSButton *)pushButtonWithTitle: (NSString *)title
                            target: (id)target
                            action: (SEL)action;

/* controlSize NSSmallControlSize gives the 17px small button height. */
+ (NSButton *)pushButtonWithTitle: (NSString *)title
                            target: (id)target
                            action: (SEL)action
                       controlSize: (NSControlSize)controlSize;

+ (NSButton *)switchWithTitle: (NSString *)title
                          state: (NSInteger)state
                        enabled: (BOOL)enabled;

/* controlSize NSSmallControlSize gives the 14px small checkbox size. */
+ (NSButton *)switchWithTitle: (NSString *)title
                          state: (NSInteger)state
                        enabled: (BOOL)enabled
                    controlSize: (NSControlSize)controlSize;

+ (NSButton *)radioWithTitle: (NSString *)title
                        state: (NSInteger)state
                      enabled: (BOOL)enabled;

+ (NSButton *)bezelButtonWithStyle: (NSBezelStyle)style side: (CGFloat)side;

+ (NSRect)inputFieldFrameWithWidth: (CGFloat)width;

/* Eau creates every text field cell unbezeled so labels look right; an
 * input field has to ask for its bezel explicitly. */
+ (id)inputFieldOfClass: (Class)fieldClass width: (CGFloat)width;

@end
