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

- (void)restart
{
  [_timer invalidate];
  _timer = [NSTimer timerWithTimeInterval: _delay
                                   target: self
                                 selector: @selector(timerFired:)
                                 userInfo: nil
                                  repeats: NO];
  NSRunLoop *rl = [NSRunLoop currentRunLoop];
  for (NSString *mode in _modes)
    {
      [rl addTimer: _timer forMode: mode];
    }
}

- (void)timerFired:(NSTimer *)timer
{
  _timer = nil;
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
