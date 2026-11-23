/* NSButton+GB.m - button keyboard handling and default-button registration
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

#import "NSButton+GB.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@implementation NSButton (GBKeyboardHandling)

+ (void) load
{
  Class cls = [NSButton class];

  // keyDown: swizzle
  {
    SEL origSelector = @selector(keyDown:);
    SEL swizSelector = @selector(gb_keyDown:);
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

  // setKeyEquivalent: swizzle - a Return key equivalent makes the button its
  // window's default button
  {
    SEL orig = @selector(setKeyEquivalent:);
    SEL swiz = @selector(gb_setKeyEquivalent:);
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
    SEL swizSelector = @selector(gb_viewDidMoveToWindow);
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
 * to a window.
 *
 * TODO: Upstream to GNUstep - a button whose key equivalent is Return should
 * become its window's default button cell by itself, as on macOS. */
- (void) gb_becomeWindowDefaultButton
{
  NSWindow *window = [self window];
  NSCell *cell = [self cell];

  if (window == nil || cell == nil)
    {
      return;
    }

  /* Whoever got there first keeps the slot - including this very cell, so a
   * repeated -setKeyEquivalent: does not make the theme tear down and rebuild
   * whatever it hangs off the window's default button. */
  if ([window defaultButtonCell] != nil)
    {
      return;
    }

  [window setDefaultButtonCell: (NSButtonCell *)cell];
}

- (void) gb_viewDidMoveToWindow
{
  [self gb_viewDidMoveToWindow];

  if ([[self keyEquivalent] isEqualToString: @"\r"])
    {
      [self gb_becomeWindowDefaultButton];
    }
}

- (void) gb_setKeyEquivalent: (NSString *)key
{
  [self gb_setKeyEquivalent: key];
  if ([key isEqualToString: @"\r"])
    {
      [self gb_becomeWindowDefaultButton];
    }
}

/* Space clicks the focused button, but Return goes to the window's default
 * button rather than to whichever button happens to have focus (macOS
 * convention).
 *
 * TODO: Upstream to GNUstep - -[NSButton keyDown:] clicks the focused button on
 * Return; it should leave Return to the window's default button cell. */
- (void) gb_keyDown: (NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];

  if ([self isEnabled] && [characters length] > 0)
    {
      unichar keyChar = [characters characterAtIndex: 0];

      if (keyChar == ' ')
        {
          [self performClick: self];
          return;
        }

      if (keyChar == '\r' || keyChar == '\n' || keyChar == 0x03)
        {
          NSWindow *win = [self window];
          id defaultCell = [win defaultButtonCell];

          if (defaultCell != nil && [defaultCell isKindOfClass: [NSButtonCell class]])
            {
              NSButton *defaultBtn = (NSButton *)[(NSButtonCell *)defaultCell controlView];
              if (defaultBtn && [defaultBtn isEnabled])
                {
                  [defaultBtn performClick: nil];
                  return;
                }
            }
          // No usable default button: let the original handle Return.
        }
    }

  [self gb_keyDown: theEvent];
}

@end
