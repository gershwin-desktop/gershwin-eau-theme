/* t_GrowBoxUnparentedView.m - a resizable window's grow box must leave
 * views alone that are not in its window.  The grow box listens to frame
 * changes of every view; an NSMatrix that is still being set up (no
 * superview, no window) gets setCellSize: and must survive it.
 *
 * Run with the theme under test, on a scratch display:
 *   DISPLAY=:N ./obj/t_GrowBoxUnparentedView -GSTheme $PWD/../Eau.theme
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import "Testing.h"

static int deallocs;

static IMP superDealloc;

static void countedDealloc(id self, SEL _cmd)
{
  deallocs++;
  ((void (*)(id, SEL))superDealloc)(self, _cmd);
}

/* Made at run time: a class defined with @implementation in a test tool
 * needs no more than this. */
static Class countedMatrixClass(void)
{
  Class c = objc_allocateClassPair([NSMatrix class], "CountedMatrix", 0);

  superDealloc = class_getMethodImplementation([NSMatrix class],
                                               @selector(dealloc));
  class_addMethod(c, @selector(dealloc), (IMP)countedDealloc, "v@:");
  objc_registerClassPair(c);
  return c;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSWindow *window;
  NSMatrix *matrix;
  Class matrixClass = countedMatrixClass();
  int i;

  [NSApplication sharedApplication];
  PASS([[[GSTheme theme] name] isEqualToString: @"Eau"], "Eau theme is active");

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                       styleMask: NSTitledWindowMask
                                                  | NSResizableWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: NO];
  [window setTitle: @"Grow box test"];
  [window orderFront: nil];
  /* The theme adds the grow box when it activates for a window; do it
   * explicitly so the test does not depend on that timing. */
  [NSClassFromString(@"EauGrowBoxView") performSelector: @selector(addToWindow:)
                                             withObject: window];
  PASS([[window contentView] viewWithTag: 0xEA0B0] != nil,
       "the window has a grow box");

  for (i = 0; i < 20; i++)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];
      NSButtonCell *proto = [[NSButtonCell new] autorelease];
      [proto setButtonType: NSRadioButton];
      matrix = [[[matrixClass alloc] initWithFrame: NSMakeRect(0, 0, 100, 50)
                                              mode: NSRadioModeMatrix
                                         prototype: proto
                                      numberOfRows: 1
                                   numberOfColumns: 2] autorelease];
      [matrix setCellSize: NSMakeSize(120 + i, 20)];
      [matrix selectCellAtRow: 0 column: 0];
      [matrix setFrame: NSMakeRect(0, 0, 130, 60)];
      [pool release];
    }
  PASS(deallocs == 20, "every unparented matrix was deallocated once (%d)", deallocs);

  /* The fix narrowed what the grow box listens to; it must still follow
   * its own window. */
  {
    NSView *content = [window contentView];
    NSView *box = [content viewWithTag: 0xEA0B0];

    [window setContentSize: NSMakeSize(420, 260)];
    PASS(fabs(NSMaxX([box frame]) - NSWidth([content bounds])) < 0.5,
         "the grow box stays in the corner after the window is resized");
  }

  [window release];
  [arp release];
  return 0;
}
