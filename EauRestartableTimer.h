/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/* Sends an action once, a fixed delay after the most recent -restart, in
 * every run loop mode it was given.  Calling -restart again before the delay
 * is over pushes the action out.  The target is not retained.  The timer
 * retains the receiver until -invalidate. */
@interface EauRestartableTimer : NSObject

- (instancetype)initWithDelay:(NSTimeInterval)delay
                       target:(id)target
                       action:(SEL)action
                        modes:(NSArray *)modes;

- (void)restart;
- (void)invalidate;

@end
