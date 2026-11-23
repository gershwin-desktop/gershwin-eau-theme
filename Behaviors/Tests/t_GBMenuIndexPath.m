/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* ObjectTesting coverage for GBMenuItemForIndexPath: an app that empties its
 * submenus and refills them in menuNeedsUpdate: (Emacs) must still have the
 * item found that Menu.app names by index path. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GBMenuIndexPath.h"

@interface LazyFiller : NSObject
@end

@implementation LazyFiller
- (void) menuNeedsUpdate: (NSMenu *)menu
{
  if ([menu numberOfItems] == 0)
    {
      [menu addItemWithTitle: @"Lazy" action: @selector(lazy:) keyEquivalent: @""];
    }
}
@end

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  LazyFiller *filler = [LazyFiller new];

  NSMenu *top = [[NSMenu alloc] initWithTitle: @"Main"];
  NSMenuItem *file = (NSMenuItem *)[top addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
  NSMenu *sub = [[NSMenu alloc] initWithTitle: @"File"];
  [sub setDelegate: filler];
  [top setSubmenu: sub forItem: file];

  PASS([sub numberOfItems] == 0, "submenu starts empty");
  NSMenuItem *found = GBMenuItemForIndexPath(top, [NSArray arrayWithObjects:
    [NSNumber numberWithInt: 0], [NSNumber numberWithInt: 0], nil]);
  PASS(found != nil && [[found title] isEqual: @"Lazy"],
       "item filled by menuNeedsUpdate: is found");

  PASS(GBMenuItemForIndexPath(top, [NSArray arrayWithObjects:
    [NSNumber numberWithInt: 0], [NSNumber numberWithInt: 5], nil]) == nil,
       "index past the end gives nil");
  PASS(GBMenuItemForIndexPath(top, [NSArray array]) == nil,
       "empty path gives nil");
  PASS(GBMenuItemForIndexPath(nil, [NSArray arrayWithObject:
    [NSNumber numberWithInt: 0]]) == nil, "nil menu gives nil");

  [pool release];
  return 0;
}
