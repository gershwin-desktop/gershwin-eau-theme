/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NSApplication category for Eau theme
 * Swizzles _lastWindowClosed to terminate by default when last window closes
 * TODO: Remove the need for this by supporting applications with no open windows in Menu
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSApplication (EauApplication)

+ (void)load {
    Class cls = [self class];
    Method orig1 = class_getInstanceMethod(cls, @selector(_lastWindowClosed));
    Method swiz1 = class_getInstanceMethod(cls, @selector(eau_lastWindowClosed));
    if (orig1 && swiz1) {
        method_exchangeImplementations(orig1, swiz1);
    }
    Method orig2 = class_getInstanceMethod(cls, @selector(_appIconInit));
    Method swiz2 = class_getInstanceMethod(cls, @selector(eau_appIconInit));
    if (orig2 && swiz2) {
        method_exchangeImplementations(orig2, swiz2);
    }
}

// Swizzled implementation that terminates by default when last window closes
- (void)eau_lastWindowClosed
{
  NSString *appName = [[NSProcessInfo processInfo] processName];
  NSString *bundleName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleExecutable"];
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  
  // Check all possible variations
  if ([appName isEqualToString:@"GWorkspace"] ||
      [appName isEqualToString:@"Workspace"] ||
      [appName isEqualToString:@"TalkSoup"] ||
      (bundleName && [bundleName isEqualToString:@"GWorkspace"]) ||
      (bundleName && [bundleName isEqualToString:@"Workspace"]) ||
      (bundlePath && [bundlePath rangeOfString:@"Workspace" options:NSCaseInsensitiveSearch].location != NSNotFound) ||
      (bundlePath && [bundlePath rangeOfString:@"GWorkspace" options:NSCaseInsensitiveSearch].location != NSNotFound))
    {
      return;  // Don't terminate these apps
    }
    
  if ([_delegate respondsToSelector:
    @selector(applicationShouldTerminateAfterLastWindowClosed:)])
    {
      if ([_delegate
        applicationShouldTerminateAfterLastWindowClosed: self])
        {
          [self terminate: self];
        }
    }
  else
    {
      // Terminate by default for all interface styles when last window closes
      // Overrides default GNUstep behavior:
      // https://github.com/gnustep/libs-gui/blob/402a94295ad56ab6219a6b18fdf9d9624834983f/Source/NSApplication.m#L4187C1-L4205C2
      [self terminate: self];
    }
}

// Swizzled implementation that prevents creation of NSIconWindow
- (void)eau_appIconInit
{
  // Do nothing to prevent creation of app icon window
}

@end