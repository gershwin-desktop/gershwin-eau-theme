/**
 * Copyright (C) 2013 Alessandro Sangiuliano
 * Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
 * Date: 31 December 2013
 *
 * Escape in a search field clears the search, under any theme.
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface NSSearchField (GB)
- (void) gb_clearSearch;
- (void) gb_keyDown: (NSEvent *)theEvent;
@end

@implementation NSSearchField (GB)

+ (void) load
{
  Class cls = [NSSearchField class];
  Method orig = class_getInstanceMethod(cls, @selector(keyDown:));
  Method swiz = class_getInstanceMethod(cls, @selector(gb_keyDown:));
  if (orig == NULL || swiz == NULL)
    return;

  /* libs-gui only implements keyDown: on NSResponder.  Exchanging the
   * inherited method would hand every responder this implementation, so the
   * original is added to NSSearchField first and only that copy is swapped. */
  if (class_addMethod(cls, @selector(keyDown:), method_getImplementation(swiz),
                      method_getTypeEncoding(swiz)))
    class_replaceMethod(cls, @selector(gb_keyDown:), method_getImplementation(orig),
                        method_getTypeEncoding(orig));
  else
    method_exchangeImplementations(orig, swiz);
}

/* Also sent by NSTextView+GB.m when Escape reaches the field editor. */
- (void) gb_clearSearch
{
  NSSearchFieldCell *cell = [self cell];
  [[self window] makeFirstResponder: nil];  // End editing
  [NSApp sendAction: [self action] to: [self target] from: self];
  [cell setStringValue: @""];

  NSText *editor = [self currentEditor];
  if (editor != nil)
    [editor setString: @""];

  [[NSNotificationCenter defaultCenter] postNotificationName: NSControlTextDidChangeNotification
                                                      object: self];
  [self setNeedsDisplay: YES];
}

- (void) gb_keyDown: (NSEvent *)theEvent
{
  NSString *chars = [theEvent charactersIgnoringModifiers];
  if ([chars length] == 1 && [chars characterAtIndex: 0] == 0x1B)
    {
      if ([[[self cell] stringValue] length] > 0)
        {
          [self gb_clearSearch];
          return;
        }
    }
  [self gb_keyDown: theEvent];
}

@end
