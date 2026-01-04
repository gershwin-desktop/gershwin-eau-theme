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
- (void) EAUselectWithFrame: (NSRect)aRect
                  inView: (NSView*)controlView
                  editor: (NSText*)textObject
                delegate: (id)anObject
                   start: (NSInteger)selStart
                  length: (NSInteger)selLength;
- (void) EAUeditWithFrame: (NSRect)aRect
                inView: (NSView*)controlView
                editor: (NSText*)textObject
              delegate: (id)anObject
                 event: (NSEvent*)theEvent;
- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView;
@end

@implementation Eau(NSTextFieldCell)
- (void) _overrideNSTextFieldCellMethod_drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  EAULOG(@"_overrideNSTextFieldCellMethod_drawInteriorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself EAUdrawInteriorWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSTextFieldCellMethod_drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  EAULOG(@"_overrideNSTextFieldCellMethod_drawWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself EAUdrawWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSTextFieldCellMethod__drawEditorWithFrame: (NSRect)cellFrame
                                                     inView: (NSView*)controlView {
  EAULOG(@"_overrideNSTextFieldCellMethod__drawEditorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself _EAUdrawEditorWithFrame:cellFrame inView:controlView];
}

- (void) _overrrideNSTextFieldCellMethod_selectWithFrame: (NSRect)aRect
                  inView: (NSView*)controlView
                  editor: (NSText*)textObject
                delegate: (id)anObject
                   start: (NSInteger)selStart
		  length: (NSInteger)selLength {
  EAULOG(@"_overrrideNSTextFieldCellMethod_selectWithFrame::::::");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself selectWithFrame:aRect
		  inView:controlView
		  editor:textObject
		delegate:anObject
		   start:selStart
		  length:selLength];
}
- (void) _overrideNSTextFieldCellMethod_editWithFrame: (NSRect)aRect
                inView: (NSView*)controlView
                editor: (NSText*)textObject
              delegate: (id)anObject
		event: (NSEvent*)theEvent {
  EAULOG(@"_overrideNSTextFieldCellMethod_editWithFrame:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself editWithFrame:aRect
		inView:controlView
		editor:textObject
	      delegate:anObject
		 event:theEvent];
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
      EAULOG(@"EAUdrawWithFrame: Drawing in normal mode - standard behavior");
    }
}

- (void) EAUdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
	NSRect titleRect;
	cellFrame.origin.y -= 1;
	cellFrame.size.height += 2;
	
  if (_cell.in_editing)
  {
	/* When editing, don't draw anything in the cell - let the text editor handle everything
	 * This creates the transparent background effect */
	return;
  }
  else
    {
      EAULOG(@"EAUdrawInteriorWithFrame: Drawing in normal mode");
	cellFrame.origin.y-= 1;
	cellFrame.size.height += 2;

       /*Make sure we are a text cell; titleRect might return an incorrect
         rectangle otherwise. Note that the type could be different if the
         user has set an image on us, which we just ignore (OS X does so as
         well).*/ 
      _cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
      [[self _drawAttributedString] drawInRect: titleRect];

    }
/*_cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
titleRect.origin.y -= 1;
titleRect.size.height += 2;
 [[self _drawAttributedString] drawInRect: titleRect];*/

}

// The cell needs to be asjusted also when is selected or edited


- (void) EAUselectWithFrame: (NSRect)aRect

                  inView: (NSView*)controlView
                  editor: (NSText*)textObject
                delegate: (id)anObject
                   start: (NSInteger)selStart
                  length: (NSInteger)selLength
{
	if (![self isMemberOfClass:[NSSearchFieldCell class]])
	{
		NSRect drawingRect = [self drawingRectForBounds: aRect];
		drawingRect.origin.x -= 4;
		drawingRect.size.width -= 0;
		drawingRect.origin.y -= 6;
		drawingRect.size.height += 11;
		[super selectWithFrame:drawingRect inView:controlView editor:textObject delegate:anObject start:selStart length:selLength];
	}
	else
	{
		[super selectWithFrame:aRect inView:controlView editor:textObject delegate:anObject start:selStart length:selLength];
	}
}

- (void) EAUeditWithFrame: (NSRect)aRect
                inView: (NSView*)controlView
                editor: (NSText*)textObject
              delegate: (id)anObject
                 event: (NSEvent*)theEvent
{
	if (![self isMemberOfClass:[NSSearchFieldCell class]])
	{
		NSRect drawingRect = [self drawingRectForBounds: aRect];
		drawingRect.origin.x += 4;
		drawingRect.size.width -= 0; //it was 6. Same in the selectWithFrame:::::: method
		drawingRect.origin.y -= 6;
		drawingRect.size.height += 11;
		[super editWithFrame:drawingRect inView:controlView editor:textObject delegate:anObject event:theEvent];
	}
	else
	{
		[super editWithFrame:aRect inView:controlView editor:textObject delegate:anObject event:theEvent];
	}



}

- (void) _EAUdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView
{
  if ([controlView isKindOfClass: [NSControl class]])
    {
      /* Don't draw any cell background when editing - this allows transparency */
      if (_cell.in_editing)
        {
          /* Just adjust the editor frame and let it handle its own drawing */
          NSRect titleRect = [self titleRectForBounds: cellFrame];
          NSText *textObject = [(NSControl*)controlView currentEditor];
          NSView *clipView = [textObject superview];
          
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
      NSText *textObject = [(NSControl*)controlView currentEditor];
      NSView *clipView = [textObject superview];
      
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
