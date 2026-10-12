/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauTestControlFactory.h"
#import "AppearanceMetrics.h"

@implementation EauTestControlFactory

+ (NSButton *)pushButtonWithTitle: (NSString *)title
                            target: (id)target
                            action: (SEL)action
{
  return [self pushButtonWithTitle: title target: target action: action
                       controlSize: NSRegularControlSize];
}

+ (NSButton *)pushButtonWithTitle: (NSString *)title
                            target: (id)target
                            action: (SEL)action
                       controlSize: (NSControlSize)controlSize
{
  CGFloat height = (controlSize == NSSmallControlSize)
    ? METRICS_BUTTON_SMALL_HEIGHT : METRICS_BUTTON_HEIGHT;
  NSButton *button = [[NSButton alloc] initWithFrame:
    NSMakeRect(0, 0, METRICS_BUTTON_MIN_WIDTH, height)];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setButtonType: NSMomentaryPushInButton];
  [[button cell] setControlSize: controlSize];
  [button setTitle: title];
  [button setTarget: target];
  [button setAction: action];
  return button;
}

+ (NSButton *)switchWithTitle: (NSString *)title
                          state: (NSInteger)state
                        enabled: (BOOL)enabled
{
  return [self switchWithTitle: title state: state enabled: enabled
                    controlSize: NSRegularControlSize];
}

+ (NSButton *)switchWithTitle: (NSString *)title
                          state: (NSInteger)state
                        enabled: (BOOL)enabled
                    controlSize: (NSControlSize)controlSize
{
  CGFloat side = (controlSize == NSSmallControlSize)
    ? METRICS_RADIO_BUTTON_SMALL_SIZE : METRICS_RADIO_BUTTON_SIZE;
  NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 90, side)];
  [button setButtonType: NSSwitchButton];
  [[button cell] setControlSize: controlSize];
  [button setTitle: title];
  [button setState: state];
  [button setEnabled: enabled];
  return button;
}

+ (NSButton *)radioWithTitle: (NSString *)title
                        state: (NSInteger)state
                      enabled: (BOOL)enabled
{
  NSButton *button = [[NSButton alloc] initWithFrame:
    NSMakeRect(0, 0, 90, METRICS_RADIO_BUTTON_SIZE)];
  [button setButtonType: NSRadioButton];
  [button setTitle: title];
  [button setState: state];
  [button setEnabled: enabled];
  return button;
}

+ (NSButton *)bezelButtonWithStyle: (NSBezelStyle)style side: (CGFloat)side
{
  NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, side, side)];
  [button setBezelStyle: style];
  [button setButtonType: NSPushOnPushOffButton];
  [button setTitle: @""];
  return button;
}

+ (NSRect)inputFieldFrameWithWidth: (CGFloat)width
{
  return NSMakeRect(0, 0, width, METRICS_TEXT_INPUT_FIELD_HEIGHT);
}

+ (id)inputFieldOfClass: (Class)fieldClass width: (CGFloat)width
{
  NSTextField *field = [[fieldClass alloc] initWithFrame:
    [self inputFieldFrameWithWidth: width]];
  [field setBezeled: YES];
  [field setEditable: YES];
  [field setDrawsBackground: YES];
  return field;
}

@end
