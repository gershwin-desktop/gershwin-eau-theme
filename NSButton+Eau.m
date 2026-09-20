/* NSButton+Eau.m - Eau theme button keyboard handling
   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the 
   Free Software Foundation, 51 Franklin Street, Fifth Floor, 
   Boston, MA 02110-1301, USA.
*/

#import "NSButton+Eau.h"
#import "Eau.h"
#import "Eau+Button.h"
#import "NSButtonCell+Eau.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSButton (EauKeyboardHandling)

+ (void) load
{
  Class cls = [NSButton class];

  // keyDown: swizzle
  {
    SEL origSelector = @selector(keyDown:);
    SEL swizSelector = @selector(eau_keyDown:);
    Method origMethod = class_getInstanceMethod(cls, origSelector);
    Method swizMethod = class_getInstanceMethod(cls, swizSelector);
    BOOL didAddMethod = class_addMethod(cls, origSelector,
                                        method_getImplementation(swizMethod),
                                        method_getTypeEncoding(swizMethod));
    if (didAddMethod)
      class_replaceMethod(cls, swizSelector,
                          method_getImplementation(origMethod),
                          method_getTypeEncoding(origMethod));
    else
      method_exchangeImplementations(origMethod, swizMethod);
  }

  // setKeyEquivalent: swizzle - when @"\r", start pulse on the cell
  {
    SEL orig = @selector(setKeyEquivalent:);
    SEL swiz = @selector(eau_setKeyEquivalent:);
    Method origM = class_getInstanceMethod(cls, orig);
    Method swizM = class_getInstanceMethod(cls, swiz);
    if (origM && swizM)
      method_exchangeImplementations(origM, swizM);
  }

  // viewDidMoveToWindow swizzle - a button that already carries the Return
  // key equivalent only learns its window here.  NSButton inherits this from
  // NSView, so add-then-replace instead of exchanging, which would swap the
  // implementation for every view in the application.
  {
    SEL origSelector = @selector(viewDidMoveToWindow);
    SEL swizSelector = @selector(eau_viewDidMoveToWindow);
    Method origMethod = class_getInstanceMethod(cls, origSelector);
    Method swizMethod = class_getInstanceMethod(cls, swizSelector);
    BOOL didAddMethod = class_addMethod(cls, origSelector,
                                        method_getImplementation(swizMethod),
                                        method_getTypeEncoding(swizMethod));
    if (didAddMethod)
      class_replaceMethod(cls, swizSelector,
                          method_getImplementation(origMethod),
                          method_getTypeEncoding(origMethod));
    else
      method_exchangeImplementations(origMethod, swizMethod);
  }
}

/* Hand this button's cell to its window as the default button cell.
 *
 * This lives on NSButton rather than on NSButtonCell because a view knows its
 * window directly, while -[NSButtonCell controlView] is nil until the cell has
 * been drawn for the first time.  The theme used to compensate for that by
 * scanning every window and every subview of the application from the cell,
 * and by retrying on a timer; that scan called -setDefaultButtonCell: back
 * into the window that was in the middle of calling it, and it still missed
 * the common case of a button that gets its key equivalent before being added
 * to a window. */
- (void) eauBecomeWindowDefaultButton
{
  NSWindow *window = [self window];
  NSCell *cell = [self cell];

  if (window == nil || cell == nil)
    {
      return;
    }

  /* Whoever got there first keeps the slot - including this very cell, so a
   * repeated -setKeyEquivalent: does not tear the window's animation
   * controller down and build it again. */
  if ([window defaultButtonCell] != nil)
    {
      return;
    }

  [window setDefaultButtonCell: (NSButtonCell *)cell];
}

- (void) eau_viewDidMoveToWindow
{
  [self eau_viewDidMoveToWindow];

  if (EauThemeIsActive() && [[self keyEquivalent] isEqualToString: @"\r"])
    {
      [self eauBecomeWindowDefaultButton];
    }
}

- (void) eau_setKeyEquivalent: (NSString *)key
{
  [self eau_setKeyEquivalent: key];
  if (EauThemeIsActive() && [key isEqualToString: @"\r"])
    {
      /* The redraw ticker that makes the pulse visible belongs to the window
       * (see DefaultButtonAnimationController in NSWindow+Eau.m), so it can
       * pause while the window is not key and stop when the default button
       * changes. */
      [(NSButtonCell *)[self cell] setIsDefaultButton: @YES];
      [self eauBecomeWindowDefaultButton];
    }
}

/**
 * Swizzled keyDown to ensure spacebar activates buttons with focus ring.
 */
- (void) eau_keyDown: (NSEvent*)theEvent
{
  NSString *characters = [theEvent characters];

  if (EauThemeIsActive() && [self isEnabled] && [characters length] > 0)
    {
      unichar keyChar = [characters characterAtIndex: 0];
      
      // Handle spacebar - activate the focused button
      if (keyChar == ' ' || keyChar == 0x20)
        {
          [self performClick: self];
          return;
        }
      
      // Handle Enter/Return — activate the window's default button,
      // not necessarily the focused button (macOS convention).
      if (keyChar == '\r' || keyChar == '\n' || keyChar == 0x03)
        {
          NSWindow *win = [self window];
          if (win)
            {
              id defaultCell = [win defaultButtonCell];
              if (defaultCell && [defaultCell respondsToSelector: @selector(performClick:)])
                {
                  // Find the NSButton that owns the default cell and click it
                  if ([defaultCell isKindOfClass: [NSButtonCell class]])
                    {
                      NSButton *defaultBtn = (NSButton *)[(NSButtonCell *)defaultCell controlView];
                      if (defaultBtn && [defaultBtn isEnabled])
                        {
                          [defaultBtn performClick: nil];
                          return;
                        }
                    }
                }
            }
          // No default button: fall through to original implementation
        }
    }
  
  // Call the original implementation (which now points to eau_keyDown)
  [self eau_keyDown: theEvent];
}

@end
