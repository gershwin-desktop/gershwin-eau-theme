/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_RestartableTimer.m - the Dock progress hide timer must fire once after
 * the last restart, in every mode it serves, and must not leave a timer
 * behind per restart.
 *
 * Eau restarts it on every draw of a progress indicator.  A timer that is
 * invalidated stays in the list of every mode it was added to until that
 * mode runs again, and the modal panel and event tracking modes may never
 * run in a process (the window manager draws a spinner into titlebars and
 * never runs either), so one dead timer per draw piled up for good.
 *
 * Headless, Foundation only.  Live NSTimer instances are counted by wrapping
 * the designated initializer and -dealloc of NSTimer.
 */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "EauRestartableTimer.h"

static long liveTimers = 0;
static IMP originalInit = NULL;
static IMP originalDealloc = NULL;

typedef id (*TimerInit)(id, SEL, NSDate *, NSTimeInterval, id, SEL, id, BOOL);

static id CountingInit(id obj, SEL sel, NSDate *fd, NSTimeInterval ti,
  id target, SEL action, id info, BOOL repeats)
{
  liveTimers++;
  return ((TimerInit)originalInit)(obj, sel, fd, ti, target, action, info,
    repeats);
}

static void CountingDealloc(id obj, SEL sel)
{
  liveTimers--;
  ((void (*)(id, SEL))originalDealloc)(obj, sel);
}

/* Every NSTimer constructor ends in this initializer; +alloc is not a
   reliable hook because the runtime may allocate without sending it. */
static void CountTimers(void)
{
  Class c = [NSTimer class];
  SEL i = @selector(initWithFireDate:interval:target:selector:userInfo:repeats:);
  SEL d = @selector(dealloc);

  originalInit = class_getMethodImplementation(c, i);
  class_replaceMethod(c, i, (IMP)CountingInit,
    method_getTypeEncoding(class_getInstanceMethod(c, i)));
  originalDealloc = class_getMethodImplementation(c, d);
  class_replaceMethod(c, d, (IMP)CountingDealloc,
    method_getTypeEncoding(class_getInstanceMethod(c, d)));
}

@interface Recorder : NSObject
{
@public
  int fired;
}
- (void) fired: (id)sender;
@end

@implementation Recorder
- (void) fired: (id)sender
{
  fired++;
}
@end

static void RunMode(NSString *mode, NSTimeInterval seconds)
{
  NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];

  while ([end timeIntervalSinceNow] > 0)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];
      [[NSRunLoop currentRunLoop] runMode: mode beforeDate: end];
      [pool release];
    }
}

static EauRestartableTimer *NewTimer(Recorder *r, NSTimeInterval delay)
{
  NSArray *modes = [NSArray arrayWithObjects: NSDefaultRunLoopMode,
    @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode", nil];

  return [[EauRestartableTimer alloc] initWithDelay: delay
                                             target: r
                                             action: @selector(fired:)
                                              modes: modes];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Recorder *r;
  EauRestartableTimer *t;
  long before;
  int i;

  CountTimers();

  /* A process whose loop only ever runs the default mode, restarting the
     timer on every draw of a spinner. */
  r = [Recorder new];
  before = liveTimers;
  t = NewTimer(r, 0.2);
  for (i = 0; i < 50; i++)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];
      [t restart];
      [pool release];
      RunMode(NSDefaultRunLoopMode, 0.005);
    }
  PASS(liveTimers - before <= 1,
    "fifty restarts leave at most one timer alive (%ld alive)",
    liveTimers - before);
  PASS(r->fired == 0, "the action waits for the delay after the last restart");
  RunMode(NSDefaultRunLoopMode, 0.35);
  PASS(r->fired == 1, "the action runs once after the last restart");
  RunMode(NSDefaultRunLoopMode, 0.35);
  PASS(r->fired == 1, "the action does not repeat by itself");
  [t restart];
  RunMode(NSDefaultRunLoopMode, 0.35);
  PASS(r->fired == 2, "a restart after firing arms it again");
  PASS(liveTimers - before <= 1,
    "firing and re-arming still keeps at most one timer alive (%ld alive)",
    liveTimers - before);
  [t invalidate];
  [t release];
  [r release];

  /* The Dock bar must also go away while a modal panel runs. */
  r = [Recorder new];
  t = NewTimer(r, 0.1);
  [t restart];
  RunMode(@"NSModalPanelRunLoopMode", 0.25);
  PASS(r->fired == 1, "the action runs while only the modal panel mode runs");
  [t invalidate];
  [t release];
  [r release];

  [arp release];
  return 0;
}
