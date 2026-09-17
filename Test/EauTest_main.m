/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* EauTest - a fixture app that renders many Eau-drawn controls and carries a
 * standard main menu, so UI tests under Tests/ can exercise the theme
 * against one known window instead of depending on other applications. */

#import <AppKit/AppKit.h>
#import "EauTestMenuBuilder.h"
#import "EauTestWindowController.h"

@interface EauTestAppDelegate : NSObject
@end

@implementation EauTestAppDelegate
{
  NSMutableArray *_controllers;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
  [NSApp setMainMenu: [EauTestMenuBuilder mainMenuForApplicationName: @"EauTest"]];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  _controllers = [NSMutableArray array];
  [self newDocument: nil];
}

- (void)newDocument:(id)sender
{
  EauTestWindowController *controller = [[EauTestWindowController alloc] init];
  [_controllers addObject: controller];
  [controller showWindow];
}

- (void)openDocument:(id)sender
{
  [[NSOpenPanel openPanel] runModal];
}

- (void)saveDocument:(id)sender
{
  [self saveDocumentAs: sender];
}

- (void)saveDocumentAs:(id)sender
{
  [[NSSavePanel savePanel] runModal];
}

@end

int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      [NSApplication sharedApplication];
      EauTestAppDelegate *delegate = [[EauTestAppDelegate alloc] init];
      [NSApp setDelegate: (id)delegate];
      [NSApp run];
    }
  return 0;
}
