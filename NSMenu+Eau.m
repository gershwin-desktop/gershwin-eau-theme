/*
   NSMenu+Eau.m

   The look of a chosen menu item: it blinks twice before the menu closes.
   Menu behavior (tracking, Menu.app, hiding the in-app bar, overflow) lives
   in GershwinBehaviors.bundle (Behaviors/NSMenu+GB.m).
*/

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <string.h>

/* Implemented by GershwinBehaviors.bundle; looked up by name so the theme
   still works without the bundle. */
@interface NSObject (EauMenuTrackingLookup)
+ (BOOL)isTracking;
@end

/* Without the bundle there is no tracking count, so no item is known to be
   chosen from an open menu and nothing blinks. */
static BOOL EauMenuIsTracking(void)
{
  Class tracking = NSClassFromString(@"GBMenuTracking");
  return tracking != Nil && [tracking isTracking];
}

@implementation NSMenu (Eau)

/**
 * Swizzled -performActionForItemAtIndex: implementation.
 *
 * Classic Mac OS (System 7) menu feedback: when the user triggers an item
 * by releasing the mouse over it, the item blinks twice (highlight,
 * unhighlight, highlight, unhighlight) before the menu closes.
 *
 * GNUstep calls this from -[NSMenuView _trackWithEvent:] AFTER the mouse
 * has been released but BEFORE the menu window is taken down and the item
 * is unhighlighted (that happens back in _trackWithEvent:).  So we can
 * blink here while the menu is still on screen.
 *
 * Ordering: we call the original implementation FIRST (firing the action
 * immediately - we must not delay the user's command while the menu
 * blinks), then perform the blink as pure visual feedback.  The action is
 * synchronous, so by the time it returns the menu window is still visible
 * and the highlight is still set - perfect for the blink.
 *
 * We only blink for mouse-driven activation: during tracking the menu
 * panel is visible and _highlightedItemIndex matches `index`.  Key
 * equivalents call this too (via performKeyEquivalent:), but then the menu
 * is normally not visible, so the visibility/highlight checks below make
 * the blink a no-op.
 */
- (void)eau_performActionForItemAtIndex:(NSInteger)index
{
  // Fire the action immediately; the blink is only visual feedback.
  [self eau_performActionForItemAtIndex:index];

  // Blink only while a menu is actively being tracked on screen.
  if (!EauMenuIsTracking()) return;

  // Blink only when the triggered item itself carries an action.  An item
  // that merely has a submenu (and nothing else) uses the no-op
  // submenuAction: that setSubmenu: installs (NSMenuItem.m:244), so it must
  // not blink - only items whose own action will actually run get the
  // feedback.  Items that have BOTH a submenu and a real action (e.g. a
  // submenu-bearing entry that also performs something on click) do blink.
  {
    id item = [self itemAtIndex: index];
    if (!item) return;
    SEL action = [item action];

    // Skip the blink for items that merely open a submenu: setSubmenu:
    // installs the no-op submenuAction: on them.  Compare by NAME, not SEL
    // pointer: the selector the item carries was registered by the host app,
    // which may not be pointer-identical to our @selector(submenuAction:)
    // even though the names match (selectors are not safely comparable
    // across bundle boundaries on this runtime).
    if (!action) return;
    {
      const char *actionName = sel_getName(action);
      if (actionName && strcmp(actionName, "submenuAction:") == 0) return;
    }
  }

  NSMenuView *view = (NSMenuView *)[self menuRepresentation];
  if (!view || ![view isKindOfClass: objc_getClass("NSMenuView")]) return;

  NSWindow *win = [view window];
  if (!win || ![win isVisible]) return;

  // Re-establish the highlight on the triggered item.
  //
  // For an item that ALSO has a submenu, GNUstep's _executeItemAtIndex:
  // (Macintosh style) calls detachSubmenu BEFORE performActionForItemAtIndex:,
  // and detachSubmenu clears the highlight (setHighlightedItemIndex: -1 in
  // upstream NSMenuView.m).  So we must SET the highlight here rather than
  // require it to still be set; otherwise submenu-bearing items would never
  // blink.  After the blink we leave the item highlighted - _trackWithEvent:
  // unhighlights it again (line 1936) so the end state is unchanged.

  // Two blink cycles.  Each cycle unhighlights briefly, then restores the
  // highlight, letting the run loop draw the intermediate states.
  const int blinkCycles = 2;
  const double blinkDuration = 0.06;
  for (int cycle = 0; cycle < blinkCycles; cycle++)
    {
      [view setHighlightedItemIndex:-1];
      [win display];
      [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:blinkDuration]];

      [view setHighlightedItemIndex:index];
      [win display];
      [[NSRunLoop currentRunLoop]
        runUntilDate:[NSDate dateWithTimeIntervalSinceNow:blinkDuration]];
    }
}

+ (void)load
{
  Method original = class_getInstanceMethod(self, @selector(performActionForItemAtIndex:));
  Method swizzled = class_getInstanceMethod(self, @selector(eau_performActionForItemAtIndex:));
  if (original == NULL || swizzled == NULL)
    {
      NSDebugLog(@"Eau: Cannot swizzle NSMenu -performActionForItemAtIndex:");
      return;
    }
  // Prevent double-swizzling on bundle reload
  if (method_getImplementation(original) == method_getImplementation(swizzled))
    return;
  method_exchangeImplementations(original, swizzled);
}

@end
