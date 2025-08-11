/**
* Copyright (C) 2013 Alessandro Sangiuliano
* Author: Alessandro Sangiuliano <alex22_7@hotmail.com>
* Date: 31 December 2013
*/

#import "Rik.h"
#import "NSTextFieldCell+Rik.h"

/* Problems just with the first click in the textbox
 * then all works as should works.
 * The Cell and the text box are not aligned on the first click.
 */

@interface NSTextFieldCell (RikTheme)
- (void) RIKdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
- (void) RIKselectWithFrame: (NSRect)aRect
                  inView: (NSView*)controlView
                  editor: (NSText*)textObject
                delegate: (id)anObject
                   start: (NSInteger)selStart
                  length: (NSInteger)selLength;
- (void) RIKeditWithFrame: (NSRect)aRect
                inView: (NSView*)controlView
                editor: (NSText*)textObject
              delegate: (id)anObject
                 event: (NSEvent*)theEvent;
- (void) _RIKdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView;
@end

@implementation Rik(NSTextFieldCell)
- (void) _overrideNSTextFieldCellMethod_drawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  RIKLOG(@"_overrideNSTextFieldCellMethod_drawInteriorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself RIKdrawInteriorWithFrame:cellFrame inView:controlView];
}

- (void) _overrideNSTextFieldCellMethod__drawEditorWithFrame: (NSRect)cellFrame
                                                     inView: (NSView*)controlView {
  RIKLOG(@"_overrideNSTextFieldCellMethod__drawEditorWithFrame:inView:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself _RIKdrawEditorWithFrame:cellFrame inView:controlView];
}

- (void) _overrrideNSTextFieldCellMethod_selectWithFrame: (NSRect)aRect
                  inView: (NSView*)controlView
                  editor: (NSText*)textObject
                delegate: (id)anObject
                   start: (NSInteger)selStart
		  length: (NSInteger)selLength {
  RIKLOG(@"_overrrideNSTextFieldCellMethod_selectWithFrame::::::");
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
  RIKLOG(@"_overrideNSTextFieldCellMethod_editWithFrame:");
  NSTextFieldCell *xself = (NSTextFieldCell*)self;
  [xself editWithFrame:aRect
		inView:controlView
		editor:textObject
	      delegate:anObject
		 event:theEvent];
}

@end

@implementation NSTextFieldCell (RikTheme)

- (void) RIKdrawInteriorWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
	NSRect titleRect;
	cellFrame.origin.y -= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -= 1;
	[self _drawEditorWithFrame: cellFrame inView: controlView];
  if (_cell.in_editing)
  {
	cellFrame.origin.y -= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -=10 ;

	[self _drawEditorWithFrame: cellFrame inView: controlView];
	//titleRect = [self titleRectForBounds: cellFrame];
	//titleRect.origin.y -= 10;
  }
  else
    {
      //NSRect titleRect;
	cellFrame.origin.y-= 1;
	cellFrame.size.height += 2;
	//cellFrame.size.width -= 10;
	//[self _drawEditorWithFrame: cellFrame inView: controlView];

       /*Make sure we are a text cell; titleRect might return an incorrect
         rectangle otherwise. Note that the type could be different if the
         user has set an image on us, which we just ignore (OS X does so as
         well).*/ 
      _cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
	//titleRect.origin.y -= 1;
	//titleRect.size.height += 2;
      [[self _drawAttributedString] drawInRect: titleRect];
	//[self _drawEditorWithFrame: cellFrame inView: controlView];

    }
/*_cell.type = NSTextCellType;
      titleRect = [self titleRectForBounds: cellFrame];
titleRect.origin.y -= 1;
titleRect.size.height += 2;
 [[self _drawAttributedString] drawInRect: titleRect];*/

}

// The cell needs to be asjusted also when is selected or edited


- (void) RIKselectWithFrame: (NSRect)aRect

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

- (void) RIKeditWithFrame: (NSRect)aRect
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

- (void) _RIKdrawEditorWithFrame: (NSRect)cellFrame
                         inView: (NSView*)controlView
{
  RIKLOG(@"_RIKdrawEditorWithFrame:inView: - Setting transparent background for text editing");
  
  if ([controlView isKindOfClass: [NSControl class]])
    {
      /* Adjust the text editor's frame to match cell's frame (w/o border) */
      NSRect titleRect = [self titleRectForBounds: cellFrame];
      NSText *textObject = [(NSControl*)controlView currentEditor];
      NSView *clipView = [textObject superview];

      RIKLOG(@"_RIKdrawEditorWithFrame: textObject=%@, clipView=%@", textObject, clipView);
      
      /* Set transparent background for the text editor */
      if (textObject != nil)
        {
          RIKLOG(@"_RIKdrawEditorWithFrame: Setting text editor background to transparent");
          [textObject setBackgroundColor: [NSColor clearColor]];
          [textObject setDrawsBackground: YES];
        }
      
      /* Set transparent background for the clip view if it exists */
      if ([clipView isKindOfClass: [NSClipView class]])
	{
          RIKLOG(@"_RIKdrawEditorWithFrame: Setting clip view background to transparent and adjusting frame");
	  [clipView setFrame: titleRect];
          [(NSClipView*)clipView setBackgroundColor: [NSColor clearColor]];
          [(NSClipView*)clipView setDrawsBackground: YES];
	}
      else if (textObject != nil)
	{
          RIKLOG(@"_RIKdrawEditorWithFrame: Setting text object frame directly");
	  [textObject setFrame: titleRect];
	}
    }
}

@end


