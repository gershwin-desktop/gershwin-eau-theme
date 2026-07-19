/**
* Copyright (C) 2013 Alessandro Sangiuliano
* Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
* Date: 31 December 2013
*/

#import "Eau.h"
#import "NSSearchField+Eau.h"

@interface NSSearchField (EauTheme)
- (void) EAUmouseDown: (NSEvent*)theEvent;
- (void) EAUcancelOperation: (id)sender;
- (BOOL) EAUtextView: (NSTextView*)textView doCommandBySelector: (SEL)commandSelector;
@end

@implementation Eau(NSSearchField)
- (void) _overrideNSSearchFieldMethod_mouseDown: (NSEvent*)theEvent {
  NSDebugLog(@"_overrideNSSearchFieldMethod_mouseDown:");
  NSSearchField *xself = (NSSearchField*)self;
  [xself EAUmouseDown: theEvent];
}

- (void) _overrideNSSearchFieldMethod_cancelOperation: (id)sender {
  NSDebugLog(@"_overrideNSSearchFieldMethod_cancelOperation:");
  NSSearchField *xself = (NSSearchField*)self;
  [xself EAUcancelOperation: sender];
}

- (BOOL) _overrideNSSearchFieldMethod_textView: (NSTextView*)textView doCommandBySelector: (SEL)commandSelector {
  NSDebugLog(@"_overrideNSSearchFieldMethod_textView:doCommandBySelector:");
  NSSearchField *xself = (NSSearchField*)self;
  return [xself EAUtextView: textView doCommandBySelector: commandSelector];
}
@end

@implementation NSSearchField (EauTheme)

- (void) EAUclearSearch
{
  NSSearchFieldCell *cell = [self cell];
  [cell setStringValue: @""];

  /* Also clear the field editor text so the display updates immediately */
  NSText *editor = [self currentEditor];
  if (editor != nil)
    {
      [editor setString: @""];
    }

  [self setNeedsDisplay: YES];

  if ([[self target] respondsToSelector: [self action]])
    {
      [NSApp sendAction: [self action] to: [self target] from: self];
    }
  else
    {
      [self sendAction: [self action] to: [self target]];
    }
}

- (void) EAUmouseDown: (NSEvent*)theEvent
{
  NSSearchFieldCell *cell = [self cell];
  NSString *val = [cell stringValue];

  /* If the search field has text, check if the click is on the cancel button */
  if ([val length] > 0)
    {
      NSRect cellFrame = [cell drawingRectForBounds: [self bounds]];
      NSRect cancelRect = [cell cancelButtonRectForBounds: cellFrame];
      NSPoint mouseLoc = [self convertPoint: [theEvent locationInWindow] fromView: nil];

      if (NSMouseInRect(mouseLoc, cancelRect, [self isFlipped]))
        {
          [self EAUclearSearch];
          return;
        }
    }

  [super mouseDown: theEvent];
}

- (void) EAUcancelOperation: (id)sender
{
  /* Esc with text in the search field clears the search */
  if ([[[self cell] stringValue] length] > 0)
    {
      [self EAUclearSearch];
    }
  else
    {
      [super cancelOperation: sender];
    }
}

- (BOOL) EAUtextView: (NSTextView*)textView doCommandBySelector: (SEL)commandSelector
{
  /* Intercept Esc (cancelOperation:) sent by the field editor to its
   * delegate (this NSSearchField). This handles the case where the
   * field editor processes cancelOperation: internally instead of
   * sending it up the responder chain to EAUcancelOperation:. */
  if (commandSelector == @selector(cancelOperation:))
    {
      if ([[[self cell] stringValue] length] > 0)
        {
          [self EAUclearSearch];
          return YES;
        }
    }
  return NO;
}

@end
