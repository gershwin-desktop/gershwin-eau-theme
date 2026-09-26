/* GBMenuSafeTriangle.m - keep a submenu open while the pointer heads to it
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* When the pointer leaves an item with an open submenu and travels
 * diagonally toward that submenu, it crosses neighbouring items.  libs-gui
 * would highlight each of them and close the submenu, so the user can only
 * reach it by moving horizontally first.  Its only mitigation keeps the
 * submenu while the pointer moves RIGHT by more than 2px for up to 10
 * periodic events, which does nothing for submenus flipped to the left at
 * the screen edge or for menu bar dropdowns.
 *
 * The "safe triangle" (apex: where the pointer left the item; base: the
 * submenu edge facing it) fixes that: while the pointer is inside it and
 * keeps moving, the highlight stays put.
 *
 * -[NSMenuView _trackWithEvent:] is a private monolithic loop, so instead of
 * replacing it we filter what it reads.  The loop does not look at mouse
 * moved/dragged events at all: on every NSPeriodic event (every 10ms) it
 * polls the live pointer position and re-evaluates the item under it.
 * Holding back periodic events while the pointer is in the triangle
 * therefore freezes the highlight without touching any other event.  As
 * soon as the pointer stops for GBMenuSafeTriangleDelay seconds, leaves
 * the triangle or enters the submenu, the next periodic event goes through
 * and normal tracking resumes from the current pointer position.
 *
 * TODO: Upstream to GNUstep - -[NSMenuView _trackWithEvent:] should apply a
 * safe-triangle test (any submenu side) instead of MOVE_THRESHOLD_DELTA.
 *
 * Menu.app's menu bar dropdowns go through the same libs-gui loop in the
 * same process, so they get this too.  Eau also chains
 * nextEventMatchingMask:untilDate:inMode:dequeue: (scroll wheel); both
 * capture whatever implementation is current, so load order does not
 * matter. */

#import "GBMenuSafeTriangle.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* Seconds the pointer may rest inside the triangle before the item under it
 * takes over; 0 disables the feature.  Matches the pause other desktops use
 * to tell "on the way" from "chose this item". */
static NSString *const GBMenuSafeTriangleDelayKey = @"GBMenuSafeTriangleDelay";
static const NSTimeInterval GBMenuSafeTriangleDefaultDelay = 0.3;

typedef NSEvent *(*GBNextEventIMP)(id, SEL, NSUInteger, NSDate *, NSString *, BOOL);
static GBNextEventIMP gb_orig_nextEvent = NULL;

/* The menu view that attached the submenu most recently.  Weak because the
 * menu can go away while no tracking loop runs. */
static __weak NSMenuView *gb_parentView = nil;
static NSInteger gb_parentIndex = -1;
static NSTimeInterval gb_delay = 0;
static BOOL gb_haveApex = NO;
static NSPoint gb_apex;
static BOOL gb_holding = NO;
static NSPoint gb_lastPoint;
static NSTimeInterval gb_lastMoveTime = 0;

static NSTimeInterval gb_readDelay(void)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:GBMenuSafeTriangleDelayKey];
  if (![value respondsToSelector:@selector(doubleValue)]) {
    return GBMenuSafeTriangleDefaultDelay;
  }
  NSTimeInterval delay = [value doubleValue];
  return delay > 0 ? delay : 0;
}

static NSRect gb_screenRectOfItem(NSMenuView *view, NSInteger index)
{
  NSRect r = [view convertRect:[view rectOfItemAtIndex:index] toView:nil];
  return [[view window] convertRectToScreen:r];
}

static void gb_resetHold(void)
{
  gb_holding = NO;
  gb_haveApex = NO;
}

/* Decides for one periodic event whether the tracking loop must not see
 * it.  Called only from inside a menu tracking loop. */
static BOOL gb_shouldHoldPeriodic(void)
{
  NSMenuView *view = gb_parentView;
  if (view == nil || gb_delay <= 0) {
    return NO;
  }

  /* The loop may have moved on (another item, keyboard navigation, menu
   * closed) since the attach we recorded; only an item still showing its
   * own submenu has a triangle. */
  NSMenu *menu = [view menu];
  NSMenu *submenu = [menu attachedMenu];
  NSWindow *submenuWindow = [submenu window];
  NSInteger index = gb_parentIndex;
  if (submenu == nil || ![submenuWindow isVisible] || [view window] == nil ||
      [view highlightedItemIndex] != index || index < 0 || index >= [menu numberOfItems] ||
      [[menu itemAtIndex:index] submenu] != submenu) {
    gb_parentView = nil;
    gb_resetHold();
    return NO;
  }

  NSPoint p = [NSEvent mouseLocation];
  NSRect submenuFrame = [submenuWindow frame];
  NSRect itemRect = gb_screenRectOfItem(view, index);

  if (NSMouseInRect(p, submenuFrame, NO)) {
    gb_resetHold();
    return NO;
  }
  if (NSMouseInRect(p, itemRect, NO)) {
    gb_holding = NO;
    gb_haveApex = YES;
    gb_apex = p;
    return NO;
  }
  if (!gb_haveApex) {
    return NO;
  }

  GBSafeTriangle t = GBSafeTriangleMake(gb_apex, itemRect, submenuFrame, [view isHorizontal]);
  if (!GBPointInSafeTriangle(p, t)) {
    /* Once out, the user has chosen another direction; do not re-arm until
     * the pointer is back on the item. */
    gb_resetHold();
    return NO;
  }

  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (!gb_holding || !NSEqualPoints(p, gb_lastPoint)) {
    gb_holding = YES;
    gb_lastPoint = p;
    gb_lastMoveTime = now;
    return YES;
  }
  if (now - gb_lastMoveTime >= gb_delay) {
    gb_resetHold();
    return NO;
  }
  return YES;
}

static NSEvent *gb_nextEventMatchingMask(id self, SEL _cmd, NSUInteger mask, NSDate *date,
                                         NSString *mode, BOOL dequeue)
{
  NSEvent *event = gb_orig_nextEvent(self, _cmd, mask, date, mode, dequeue);

  /* Only the menu tracking loop asks for periodic events in the tracking
   * mode; a peek (dequeue NO) must see the queue as it is. */
  if (gb_parentView == nil || !dequeue || (mask & NSPeriodicMask) == 0 ||
      ![mode isEqualToString:NSEventTrackingRunLoopMode]) {
    return event;
  }

  /* Swallowed events are replaced by the next one from the queue with the
   * caller's own deadline, so the caller never waits longer than it asked. */
  while (event != nil && [event type] == NSPeriodic && gb_shouldHoldPeriodic()) {
    event = gb_orig_nextEvent(self, _cmd, mask, date, mode, dequeue);
  }
  return event;
}

@interface NSMenuView (GBMenuSafeTriangle)
- (void)gb_attachSubmenuForItemAtIndex:(NSInteger)index;
@end

@implementation NSMenuView (GBMenuSafeTriangle)

- (void)gb_attachSubmenuForItemAtIndex:(NSInteger)index
{
  [self gb_attachSubmenuForItemAtIndex:index];

  gb_parentView = self;
  gb_parentIndex = index;
  gb_holding = NO;
  gb_delay = gb_readDelay();

  /* A submenu opened from the keyboard has no pointer exit point, so it
   * gets a triangle only once the pointer has been on the item. */
  NSRect itemRect = gb_screenRectOfItem(self, index);
  NSPoint p = [NSEvent mouseLocation];
  gb_haveApex = NSMouseInRect(p, itemRect, NO);
  gb_apex = p;
}

/* In the category rather than a class of its own: a category's +load runs
 * only after its methods are attached, so gb_attachSubmenuForItemAtIndex:
 * is guaranteed to exist here. */
+ (void)load
{
  Class viewClass = [NSMenuView class];
  SEL attachSel = @selector(attachSubmenuForItemAtIndex:);
  SEL gbAttachSel = @selector(gb_attachSubmenuForItemAtIndex:);
  Method attach = class_getInstanceMethod(viewClass, attachSel);
  Method gbAttach = class_getInstanceMethod(viewClass, gbAttachSel);
  Method next = class_getInstanceMethod([NSApplication class],
                                        @selector(nextEventMatchingMask:untilDate:inMode:dequeue:));
  if (attach == NULL || gbAttach == NULL || next == NULL) {
    NSLog(@"GershwinBehaviors: menu safe triangle not installed");
    return;
  }

  /* Add first so an inherited implementation is not exchanged on the
   * superclass. */
  if (class_addMethod(viewClass, attachSel, method_getImplementation(attach),
                      method_getTypeEncoding(attach))) {
    attach = class_getInstanceMethod(viewClass, attachSel);
  }
  method_exchangeImplementations(attach, gbAttach);

  IMP orig = method_getImplementation(next);
  memcpy(&gb_orig_nextEvent, &orig, sizeof(gb_orig_nextEvent));
  method_setImplementation(next, (IMP)gb_nextEventMatchingMask);
}

@end
