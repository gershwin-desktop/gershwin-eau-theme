/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauRestartableTimer.h"

@implementation EauRestartableTimer
{
  NSTimeInterval _delay;
  __weak id _target;
  SEL _action;
  NSArray *_modes;
  NSTimer *_timer;
}

- (instancetype)initWithDelay:(NSTimeInterval)delay
                       target:(id)target
                       action:(SEL)action
                        modes:(NSArray *)modes
{
  if ((self = [super init]) != nil)
    {
      _delay = delay;
      _target = target;
      _action = action;
      _modes = [modes copy];
    }
  return self;
}

/* One repeating timer, added to the modes once and then only moved in time.
 * Invalidating a timer and scheduling a new one per restart would leave the
 * old one in the list of every mode that does not run meanwhile (a modal
 * panel mode in a process that never shows one), one dead timer per restart
 * for the life of the process. */
- (void)restart
{
  if (_timer == nil)
    {
      _timer = [[NSTimer alloc] initWithFireDate: [NSDate distantFuture]
                                        interval: _delay
                                          target: self
                                        selector: @selector(timerFired:)
                                        userInfo: nil
                                         repeats: YES];
      NSRunLoop *rl = [NSRunLoop currentRunLoop];
      for (NSString *mode in _modes)
        {
          [rl addTimer: _timer forMode: mode];
        }
    }
  [_timer setFireDate: [NSDate dateWithTimeIntervalSinceNow: _delay]];
}

- (void)timerFired:(NSTimer *)timer
{
  /* Parked rather than invalidated, for the reason given at -restart. */
  [_timer setFireDate: [NSDate distantFuture]];
  id target = _target;
  if (target != nil)
    {
      /* The action is the caller's; ARC cannot see its ownership semantics,
       * and the actions used here return nothing. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
      [target performSelector: _action withObject: self];
#pragma clang diagnostic pop
    }
}

- (void)invalidate
{
  [_timer invalidate];
  _timer = nil;
}

@end
