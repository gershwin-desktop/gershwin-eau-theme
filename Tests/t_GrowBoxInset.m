/* t_GrowBoxInset.m - the grow box sits in the bottom-right corner of a
 * resizable window, raised above the corner when the window's bottom edge
 * ends higher at the right side (a curved outline says so with
 * -resizeIndicatorBottomInset), so the grip is never cut off.
 *
 * Runs with the plain GNUstep theme; needs DISPLAY.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "EauGrowBoxView.h"

@interface CurvedWindow : NSWindow
@end

@implementation CurvedWindow
- (CGFloat) resizeIndicatorBottomInset
{
  return 8.0;
}
@end

static NSView *growBoxIn(NSWindow *window)
{
  for (NSView *view in [[window contentView] subviews])
    {
      if ([view isKindOfClass: [EauGrowBoxView class]])
        return view;
    }
  return nil;
}

static NSWindow *makeWindow(Class cls)
{
  return [[cls alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                styleMask: NSTitledWindowMask | NSResizableWindowMask
                                  backing: NSBackingStoreBuffered
                                    defer: YES];
}

int main(int argc, char **argv)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *args = [NSMutableDictionary dictionaryWithDictionary:
    [defs volatileDomainForName: NSArgumentDomain]];
  [args setObject: @"GNUstep" forKey: @"GSTheme"];
  [defs removeVolatileDomainForName: NSArgumentDomain];
  [defs setVolatileDomain: args forName: NSArgumentDomain];
  [NSApplication sharedApplication];

  START_SET("plain window")
    NSWindow *window = makeWindow([NSWindow class]);
    [EauGrowBoxView addToWindow: window];
    NSView *box = growBoxIn(window);
    NSRect content = [[window contentView] bounds];
    PASS(box != nil, "a resizable window gets a grow box");
    PASS(NSMinY([box frame]) == 0 && NSMaxX([box frame]) == NSMaxX(content),
         "in the bottom-right corner");
  END_SET("plain window")

  START_SET("window with a curved bottom")
    NSWindow *window = makeWindow([CurvedWindow class]);
    [EauGrowBoxView addToWindow: window];
    NSView *box = growBoxIn(window);
    PASS(NSMinY([box frame]) == 8.0
         && NSMaxX([box frame]) == NSMaxX([[window contentView] bounds]),
         "the grow box sits above where the edge ends at the right side");
    [window setContentSize: NSMakeSize(400, 260)];
    PASS(NSMinY([box frame]) == 8.0
         && NSMaxX([box frame]) == NSMaxX([[window contentView] bounds]),
         "and stays there when the window is resized");
  END_SET("window with a curved bottom")

  [arp release];
  return 0;
}
