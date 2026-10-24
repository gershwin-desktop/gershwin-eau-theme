/**
* Copyright (C) 2013 Alessandro Sangiuliano
* Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
* Date: 31 December 2013
*/

#import "Eau.h"
#import "NSTextFieldCell+Eau.h"

/* Problems just with the first click in the textbox
 * then all works as should works.
 * The Cell and the text box are not aligned on the first click.
 */

@interface NSTextFieldCell (EauTheme)
- (void) EAUdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
- (void) EAUdrawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView;
@end

/* Implemented in libs-gui's NSCell.m */
@interface NSCell (EauTruncation)
- (BOOL) _shouldShortenStringForRect: (NSRect)titleRect
                                size: (NSSize)titleSize
                              length: (NSUInteger)length;
- (NSAttributedString*) _resizeAttributedString: (NSAttributedString*)attrstring
                                         forRect: (NSRect)titleRect;
@end

@implementation Eau(NSTextFieldCell)
- (void) _overrideNSTextFieldCellMethod_drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSTextFieldCellMethod_drawInteriorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself EAUdrawInteriorWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSTextFieldCellMethod_drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSTextFieldCellMethod_drawWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself EAUdrawWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSTextFieldCellMethod__drawEditorWithFrame: (NSRect)cellFrame
                                                     inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSTextFieldCellMethod__drawEditorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself _EAUdrawEditorWithFrame:cellFrame inView:controlView];
}


@end

@implementation NSTextFieldCell (EauTheme)

- (void) EAUdrawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  /* Always draw the border/bezel, regardless of editing state */
  [super drawWithFrame:cellFrame inView:controlView];
  
  if (_cell.in_editing)
    {
      /* Border is drawn by super, but interior will be handled by drawInteriorWithFrame
       * which will skip drawing to create transparency */
    }
  else
    {
      NSDebugLog(@"EAUdrawWithFrame: Drawing in normal mode - standard behavior");
    }
}

- (void) EAUdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
	NSRect titleRect;
	// cellFrame.origin.y -= 1;
	// cellFrame.size.height += 2;
	
  if (_cell.in_editing)
  {
	/* When editing, don't draw anything in the cell - let the text editor handle everything
	 * This creates the transparent background effect */
	return;
  }
  else
    {
      NSDebugLog(@"EAUdrawInteriorWithFrame: Drawing in normal mode");
	// cellFrame.origin.y-= 1;
	// cellFrame.size.height += 2;

       /*Make sure we are a text cell; titleRect might return an incorrect
         rectangle otherwise. Note that the type could be different if the
         user has set an image on us, which we just ignore (OS X does so as
         well).*/ 
      _cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
      NSAttributedString *text = [self _drawAttributedString];
      /* Honour the truncating line break modes like NSCell does: text too
       * long for the field is shortened with an ellipsis at the head, in
       * the middle or at the tail, instead of being clipped. */
      if ([self _shouldShortenStringForRect: titleRect
                                       size: [text size]
                                     length: [text length]])
        {
          text = [self _resizeAttributedString: text forRect: titleRect];
        }
      [text drawInRect: titleRect];

    }
/*_cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
titleRect.origin.y -= 1;
titleRect.size.height += 2;
 [[self _drawAttributedString] drawInRect: titleRect];*/

}



- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView
{
  if ([controlView isKindOfClass: [NSControl class]])
    {
      NSText *textObject = [(NSControl*)controlView currentEditor];

      /* Make the editor background transparent so the rounded bezel shows through */
      [textObject setDrawsBackground: NO];
      [textObject setBackgroundColor: [NSColor clearColor]];

      NSView *clipView = [textObject superview];
      if ([clipView isKindOfClass: [NSClipView class]])
        {
          [(id)clipView setDrawsBackground: NO];
        }

      if (_cell.in_editing)
        {
          /* Just adjust the editor frame and let it handle its own drawing */
          NSRect titleRect = [self titleRectForBounds: cellFrame];
          
          if ([clipView isKindOfClass: [NSClipView class]])
            {
              [clipView setFrame: titleRect];
            }
          else if (textObject != nil)
            {
              [textObject setFrame: titleRect];
            }
          
          return; /* Exit early - don't call super to avoid background drawing */
        }
      
      /* For non-editing mode, use standard behavior */
      NSRect titleRect = [self titleRectForBounds: cellFrame];
      
      if ([clipView isKindOfClass: [NSClipView class]])
        {
          [clipView setFrame: titleRect];
        }
      else if (textObject != nil)
        {
          [textObject setFrame: titleRect];
        }
    }
}

@end

// A text field the user can type into keeps the bezel and the white
// background that AppKit gives it; one that cannot be edited is a label or a
// read-only value and has neither.  What an app builds in code is editable
// until it says otherwise, so the change is made when it does: an
// application that sets bezeled or drawsBackground itself afterwards keeps
// what it chose, and a field made editable again gets back what this took
// from it.  Fields loaded from a nib are left as the nib has them.
@interface NSTextField (EauEditableBezel)
- (void)eauSetEditable:(BOOL)flag;
@end

static const char EauBezelRemovedKey;
static const char EauBackgroundRemovedKey;

@implementation NSTextField (EauEditableBezel)

- (void)eauSetEditable:(BOOL)flag
{
  [self eauSetEditable:flag];
  if (!EauThemeIsActive())
    {
      return;
    }
  if (flag == NO)
    {
      if ([self isBezeled])
        {
          [self setBezeled: NO];
          objc_setAssociatedObject(self, &EauBezelRemovedKey, @YES,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      /* Only the plain white of an input field; a colour the app chose
       * for a read-only field stays. */
      if ([self drawsBackground]
          && [[self backgroundColor] isEqual: [NSColor textBackgroundColor]])
        {
          [self setDrawsBackground: NO];
          objc_setAssociatedObject(self, &EauBackgroundRemovedKey, @YES,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
  else
    {
      if (objc_getAssociatedObject(self, &EauBezelRemovedKey) != nil)
        {
          [self setBezeled: YES];
          objc_setAssociatedObject(self, &EauBezelRemovedKey, nil,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
      if (objc_getAssociatedObject(self, &EauBackgroundRemovedKey) != nil)
        {
          [self setDrawsBackground: YES];
          objc_setAssociatedObject(self, &EauBackgroundRemovedKey, nil,
                                   OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

@end

__attribute__((constructor))
static void initNSTextFieldEditableBezel(void)
{
  Class cls = [NSTextField class];
  if (!cls)
    {
      return;
    }

  Method orig = class_getInstanceMethod(cls, @selector(setEditable:));
  Method swz = class_getInstanceMethod(cls, @selector(eauSetEditable:));
  if (orig && swz)
    {
      method_exchangeImplementations(orig, swz);
    }
}
