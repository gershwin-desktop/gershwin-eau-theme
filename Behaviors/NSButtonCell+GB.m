/* NSButtonCell+GB.m - default-button keyboard wiring for button cells
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "NSButtonCell+GB.h"
#import <AppKit/AppKit.h>

@implementation NSButtonCell (GBDefaultButton)

- (void) gb_adoptReturnKeyEquivalent
{
  /* Never force the cell highlighted here: a permanently highlighted cell
   * cannot show the pressed state any more, and the theme already draws the
   * default button distinctly. */
  NSView *controlView = [self controlView];

  if (controlView == nil || ![controlView isKindOfClass: [NSButton class]])
    {
      NSDebugLog(@"NSButtonCell+GB: no button for cell %p yet", self);
      return;
    }

  NSButton *button = (NSButton *)controlView;

  /* Going through the button (not the cell) also registers the cell as its
   * window's default button - see -[NSButton gb_setKeyEquivalent:]. */
  [button setKeyEquivalent: @"\r"];
  [button setNeedsDisplay: YES];

  /* Move focus to the default button only when focus already sits on another
   * button; taking it from a text field would stop the user typing. */
  NSWindow *window = [button window];
  NSResponder *current = [window firstResponder];
  if (current != nil && [current isKindOfClass: [NSButton class]])
    {
      [window makeFirstResponder: button];
    }
}

@end
