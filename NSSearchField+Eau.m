/**
 * Copyright (C) 2013 Alessandro Sangiuliano
 * Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
 * Date: 31 December 2013
 */

#import "Eau.h"
#import "NSSearchField+Eau.h"
#import <objc/runtime.h>

@implementation NSSearchField (EauTheme)

+ (void) load
{
  Class searchCls = [NSSearchField class];
  SEL keySel = @selector(keyDown:);
  Method swizm = class_getInstanceMethod(searchCls, @selector(eau_keyDown:));
  Method km = class_getInstanceMethod(searchCls, keySel);

  if (km == NULL || swizm == NULL)
    return;
  /* NSSearchField inherits keyDown: from NSResponder.  Exchanging that
     inherited method would patch NSResponder for every class: a subclass that
     calls [super keyDown:] (NSButton does) lands in eau_keyDown:, whose
     [self eau_keyDown:] then dispatches to that subclass's own eau_keyDown:
     and recurses until the stack overflows.  Give NSSearchField its own
     keyDown: so only search fields are affected. */
  if (class_addMethod(searchCls, keySel, method_getImplementation(swizm),
                      method_getTypeEncoding(swizm)))
    class_replaceMethod(searchCls, @selector(eau_keyDown:),
                        method_getImplementation(km), method_getTypeEncoding(km));
  else
    method_exchangeImplementations(km, swizm);
}

- (void) eau_clearSearch
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

- (void) eau_keyDown: (NSEvent*)theEvent
{
  NSString *chars = [theEvent charactersIgnoringModifiers];
  if ([chars length] == 1 && [chars characterAtIndex: 0] == 0x1B)
    {
      if ([[[self cell] stringValue] length] > 0)
        {
          [self eau_clearSearch];
          return;
        }
    }
  [self eau_keyDown: theEvent];
}

@end