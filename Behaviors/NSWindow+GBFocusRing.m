/* NSWindow+GBFocusRing.m - when keyboard focus rings may show
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "GBTheme.h"
#import "GBThemeHooks+FocusRing.h"

/* macOS only reveals keyboard focus rings after the user starts tabbing (full
 * keyboard access); on window open, and after any mouse interaction, the ring
 * stays hidden even though a control is the first responder.  This file owns
 * that policy; the theme is told about every change and does the drawing. */
static BOOL gbKeyboardFocusVisible = NO;

static void GBSetKeyboardFocusVisible(BOOL visible, NSWindow *window)
{
  if (gbKeyboardFocusVisible == visible)
    {
      return;
    }
  gbKeyboardFocusVisible = visible;
  [GBThemeIfResponds(@selector(gbKeyboardFocusVisibilityChanged:inWindow:))
    gbKeyboardFocusVisibilityChanged: visible
                            inWindow: window];
}

@interface NSWindow (GBFocusRing)
- (void) gb_selectNextKeyView: (id)sender;
- (void) gb_selectPreviousKeyView: (id)sender;
- (void) gb_focusRingSendEvent: (NSEvent *)event;
@end

@implementation NSWindow (GBFocusRing)

+ (void) load
{
  Class cls = [NSWindow class];

  if (class_respondsToSelector(cls, @selector(selectNextKeyView:)))
    {
      Method orig = class_getInstanceMethod(cls, @selector(selectNextKeyView:));
      Method swiz = class_getInstanceMethod(cls, @selector(gb_selectNextKeyView:));
      method_exchangeImplementations(orig, swiz);
    }
  if (class_respondsToSelector(cls, @selector(selectPreviousKeyView:)))
    {
      Method orig = class_getInstanceMethod(cls, @selector(selectPreviousKeyView:));
      Method swiz = class_getInstanceMethod(cls, @selector(gb_selectPreviousKeyView:));
      method_exchangeImplementations(orig, swiz);
    }
  Method sm = class_getInstanceMethod(cls, @selector(sendEvent:));
  Method sSwiz = class_getInstanceMethod(cls, @selector(gb_focusRingSendEvent:));
  if (sm != NULL && sSwiz != NULL)
    method_exchangeImplementations(sm, sSwiz);
}

- (void) gb_selectNextKeyView: (id)sender
{
  GBSetKeyboardFocusVisible(YES, self);
  [self gb_selectNextKeyView: sender];
}

- (void) gb_selectPreviousKeyView: (id)sender
{
  GBSetKeyboardFocusVisible(YES, self);
  [self gb_selectPreviousKeyView: sender];
}

- (void) gb_focusRingSendEvent: (NSEvent *)event
{
  NSEventType t = [event type];
  if (t == NSLeftMouseDown || t == NSRightMouseDown
      || t == NSOtherMouseDown || t == NSScrollWheel)
    {
      GBSetKeyboardFocusVisible(NO, self);
    }
  else if (t == NSKeyDown)
    {
      /* Tab (and Shift-Tab) is the only thing that reveals the ring,
       * regardless of how GNUstep routes the key (performKeyEquivalent or
       * selectNextKeyView:).  Set the flag before the event is dispatched so
       * the newly focused control paints its ring. */
      NSString *chars = [event charactersIgnoringModifiers];
      if ([chars length] > 0)
        {
          unichar k = [chars characterAtIndex: 0];
          if (k == NSTabCharacter || k == NSBackTabCharacter)
            {
              GBSetKeyboardFocusVisible(YES, self);
            }
        }
    }
  [self gb_focusRingSendEvent: event];
}

@end
