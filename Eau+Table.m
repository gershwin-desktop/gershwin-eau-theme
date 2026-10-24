#import "Eau.h"
#import "Eau+Drawings.h"

/* Private NSTableView hooks used by our drawOutlineViewRow override; these
 * exist in the gui library but have no public header. */
@interface NSTableView (EauPrivateHooks)
- (id)_objectValueForTableColumn: (NSTableColumn *)tb
			     row: (NSInteger)index;
- (void)_willDisplayCell: (NSCell *)cell
	  forTableColumn: (NSTableColumn *)tb
		     row: (NSInteger)index;
- (void)_calculatedStartingColumn: (NSInteger *)startingColumn
		      endingColumn: (NSInteger *)endingColumn
			inClipRect: (NSRect)clipRect;
@end

@interface NSCell (EauPrivateHooks)
- (void)setShowsFirstResponder: (BOOL)flag;
@end

@interface Eau(EauTable)

@end

/* A selection is drawn in the accent colour only where typing would act on
 * it: in the key window, with the table (or an editor in it) taking the
 * keys.  Everywhere else it is grey, so the one place the
 * keyboard goes stands out, as on the reference system. */
static BOOL EauTableSelectionIsActive(NSTableView *tableView)
{
  NSWindow *window = [tableView window];
  NSResponder *responder = [window firstResponder];

  if ([window isKeyWindow] == NO)
    {
      return NO;
    }
  if (responder == tableView)
    {
      return YES;
    }
  /* A cell's editor, or a rename field placed over a row (Workspace's
   * list view), keeps the row it edits in the accent colour. */
  if ([responder isKindOfClass: [NSText class]])
    {
      id delegate = [(NSText *)responder delegate];

      return (delegate == (id)tableView
              || ([delegate isKindOfClass: [NSView class]]
                  && [(NSView *)delegate isDescendantOf: tableView]));
    }
  return NO;
}

@implementation Eau(EauTable)

/* The text colour of a selected row's cells; nil leaves the cell's own
 * colour, which is what an inactive (grey) selection shows. */
- (NSColor *) eauTextColorForSelectedRow: (NSInteger)rowIndex
                             inTableView: (NSTableView *)tableView
{
  if ([tableView isRowSelected: rowIndex] == NO
      || EauTableSelectionIsActive(tableView) == NO)
    {
      return nil;
    }
  return [self colorNamed: @"highlightedTableRowTextColor"
                    state: GSThemeNormalState];
}

- (void) eauDrawCell: (NSCell *)cell
           withFrame: (NSRect)frame
              inView: (NSTableView *)tableView
           textColor: (NSColor *)textColor
{
  NSColor *saved = nil;
  BOOL swap = (textColor != nil && [cell isKindOfClass: [NSTextFieldCell class]]);

  if (swap)
    {
      saved = [(NSTextFieldCell *)cell textColor];
      [(NSTextFieldCell *)cell setTextColor: textColor];
    }
  [cell drawWithFrame: frame inView: tableView];
  if (swap)
    {
      [(NSTextFieldCell *)cell setTextColor: saved];
    }
}

- (void) highlightTableViewSelectionInClipRect: (NSRect)clipRect
                                        inView: (NSView *)view
                              selectingColumns: (BOOL)selectingColumns
{
  NSTableView *tableView = (NSTableView *)view;
  NSString *name = EauTableSelectionIsActive(tableView)
    ? @"highlightedTableRowBackgroundColor"
    : @"inactiveHighlightedTableRowBackgroundColor";
  NSIndexSet *indexes = selectingColumns
    ? [tableView selectedColumnIndexes] : [tableView selectedRowIndexes];
  NSUInteger index;

  [[self colorNamed: name state: GSThemeNormalState] set];
  for (index = [indexes firstIndex]; index != NSNotFound;
       index = [indexes indexGreaterThanIndex: index])
    {
      NSRect rect = selectingColumns
        ? [tableView rectOfColumn: index] : [tableView rectOfRow: index];

      if (NSIntersectsRect (rect, clipRect))
        {
          NSRectFill (NSIntersectionRect (rect, clipRect));
        }
    }
}

/* The gui library's row drawing with one text colour for every selected
 * row; this one picks it by whether the selection is active. */
- (void) drawTableViewRow: (NSInteger)rowIndex
                 clipRect: (NSRect)clipRect
                   inView: (NSTableView *)tableView
{
  NSInteger editedRow = [tableView editedRow];
  NSInteger editedColumn = [tableView editedColumn];
  NSArray *tableColumns = [tableView tableColumns];
  NSColor *textColor = [self eauTextColorForSelectedRow: rowIndex
                                            inTableView: tableView];
  NSInteger startingColumn;
  NSInteger endingColumn;
  NSInteger i;

  [tableView _calculatedStartingColumn: &startingColumn
                          endingColumn: &endingColumn
                            inClipRect: clipRect];

  for (i = startingColumn; i <= endingColumn; i++)
    {
      NSTableColumn *tb = [tableColumns objectAtIndex: i];
      NSCell *cell = [tb dataCellForRow: rowIndex];
      BOOL editing = (i == editedColumn && rowIndex == editedRow);

      [tableView _willDisplayCell: cell
                   forTableColumn: tb
                              row: rowIndex];
      if (editing)
        {
          [cell _setInEditing: YES];
        }
      else
        {
          [cell setObjectValue: [tableView _objectValueForTableColumn: tb
                                                                  row: rowIndex]];
        }
      [self eauDrawCell: cell
              withFrame: [tableView frameOfCellAtColumn: i row: rowIndex]
                 inView: tableView
              textColor: editing ? nil : textColor];
      if (editing)
        {
          [cell _setInEditing: NO];
        }
    }
}


- (NSRect) tableHeaderCellDrawingRectForBounds: (NSRect)theRect
{
  NSSize borderSize;

  // This adjustment must match the drawn border
  borderSize = NSMakeSize(0, 0);

  return NSInsetRect(theRect, borderSize.width, borderSize.height);
}

- (NSTextAlignment) tableHeaderCellTextAlignment
{
  // Make table headers left-aligned instead of centered
  return NSLeftTextAlignment;
}

- (NSColor *) tableHeaderTextColorForState: (GSThemeControlState)state
{
  NSColor *color;

  if (state == GSThemeHighlightedState)
    color = [NSColor controlTextColor];
  else
    color = [NSColor controlTextColor];
  return color;
}

- (NSFont *) tableHeaderFontOfSize: (CGFloat)fontSize
{
  // Use small system font (11pt) for table headers
  return [NSFont systemFontOfSize: 11];
}

- (CGFloat) tableHeaderRowHeight
{
  // Return a smaller height (17px) for table headers to match the small font
  return 17.0;
}

- (void) drawTableCornerView: (NSView*)cornerView
                   withClip: (NSRect)aRect
{
  NSRect divide;
  NSRect rect;

  if ([cornerView isFlipped])
    {
      NSDivideRect(aRect, &divide, &rect, 1.0, NSMaxYEdge);
    }
  else
    {
      NSDivideRect(aRect, &divide, &rect, 1.0, NSMinYEdge);
    }

      NSColor * basecolor = [EauSafeCalibratedRGB([NSColor controlBackgroundColor]) shadowWithLevel: 0.1];
      NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: basecolor];
      [buttonBackgroundGradient drawInRect: rect angle: -90];
      NSBezierPath* linesPath = [NSBezierPath bezierPath];
      [linesPath setLineWidth: 1];
      // Removed vertical lines - only draw horizontal lines
      [linesPath moveToPoint: NSMakePoint(rect.origin.x, NSMinY(rect))];
      [linesPath lineToPoint: NSMakePoint(rect.origin.x + rect.size.width, NSMinY(rect))];

        [linesPath moveToPoint: NSMakePoint(rect.origin.x, NSMaxY(rect))];
        [linesPath lineToPoint: NSMakePoint(rect.origin.x + rect.size.width, NSMaxY(rect))];
        NSColor * strokeColor = [NSColor colorWithCalibratedRed: 0.70
                                                          green: 0.70
                                                          blue: 0.70
                                                          alpha: 1.0];
              [strokeColor setStroke];
              [linesPath stroke];
}

- (void) drawTableHeaderCell: (NSTableHeaderCell *)cell
                   withFrame: (NSRect)cellFrame
                      inView: (NSView *)controlView
                       state: (GSThemeControlState)state
{
      // TS: unused
      // NSRect rect;

      // Leave a 1pt thick horizontal line underneath the header
      if (![controlView isFlipped])
        {
          cellFrame.origin.y++;
        }
      //cellFrame.size.height--;
      NSColor * basecolor;
      if (state == GSThemeHighlightedState)
        {
          basecolor = [NSColor selectedControlColor];
        }
      else
        {
          basecolor = [EauSafeCalibratedRGB([NSColor controlBackgroundColor]) shadowWithLevel: 0.1];
        }
        NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: basecolor];
        [buttonBackgroundGradient drawInRect: cellFrame angle: -90];

        NSBezierPath* linesPath = [NSBezierPath bezierPath];
        [linesPath setLineWidth: 1];
        // Removed vertical line - only draw horizontal lines
        // [linesPath moveToPoint: NSMakePoint(cellFrame.origin.x-0.5, NSMinY(cellFrame) + 5)];
        // [linesPath lineToPoint: NSMakePoint(cellFrame.origin.x-0.5, NSMaxY(cellFrame) - 5)];

        [linesPath moveToPoint: NSMakePoint(cellFrame.origin.x, NSMinY(cellFrame))];
        [linesPath lineToPoint: NSMakePoint(cellFrame.origin.x + cellFrame.size.width, NSMinY(cellFrame))];

        [linesPath moveToPoint: NSMakePoint(cellFrame.origin.x, NSMaxY(cellFrame))];
        [linesPath lineToPoint: NSMakePoint(cellFrame.origin.x + cellFrame.size.width, NSMaxY(cellFrame))];

        NSColor * strokeColor = [NSColor colorWithCalibratedRed: 0.70
                                                          green: 0.70
                                                          blue: 0.70
                                                          alpha: 1.0];
              [strokeColor setStroke];
              [linesPath stroke];
}

/* GNUstep's default row drawing calls the delegate's willDisplayCell before
 * setObjectValue:, so a title a delegate installs in willDisplayCell is
 * wiped by the data source value and the row renders empty (apps written
 * against macOS semantics set cell content in willDisplayCell). Setting the
 * content first and calling the delegate last restores that order without
 * patching the gui library.
 * TODO: Upstream to GNUstep - GSTheme's table/outline row drawing should call
 * setObjectValue: before the delegate's willDisplayCell:, as Cocoa does. */
- (void) drawOutlineViewRow: (NSInteger)rowIndex
		    clipRect: (NSRect)clipRect
		      inView: (NSOutlineView *)outlineView
{
  NSInteger editedRow = [outlineView editedRow];
  NSInteger editedColumn = [outlineView editedColumn];
  NSArray *tableColumns = [outlineView tableColumns];
  NSInteger numberOfRows = [outlineView numberOfRows];
  NSInteger startingColumn;
  NSInteger endingColumn;
  NSRect drawingRect;
  NSInteger i;
  NSTableColumn *outlineTableColumn = [outlineView outlineTableColumn];
  NSColor *selectedTextColor = [self eauTextColorForSelectedRow: rowIndex
                                                    inTableView: outlineView];

  if (rowIndex >= numberOfRows)
    {
      return;
    }

  [outlineView _calculatedStartingColumn: &startingColumn
			    endingColumn: &endingColumn
			      inClipRect: clipRect];

  for (i = startingColumn; i <= endingColumn; i++)
    {
      id item = [outlineView itemAtRow: rowIndex];
      NSTableColumn *tb = [tableColumns objectAtIndex: i];
      NSCell *cell = [outlineView preparedCellAtColumn: i row: rowIndex];
      BOOL editing = (i == editedColumn && rowIndex == editedRow);

      /* Content first, then the delegate's customizations. While editing,
       * leave the cell alone so it keeps the editor's value. */
      if (!editing)
        {
          id value = [outlineView _objectValueForTableColumn: tb
							 row: rowIndex];
          [cell setObjectValue: value];
        }
      [outlineView _willDisplayCell: cell
		     forTableColumn: tb
				row: rowIndex];

      if (editing)
        {
          [cell _setInEditing: YES];
          [cell setShowsFirstResponder: YES];
        }

      drawingRect = [outlineView frameOfCellAtColumn: i
						 row: rowIndex];

      if (tb == outlineTableColumn)
        {
          drawingRect = [self drawOutlineCell: tb
				  outlineView: outlineView
					 item: item
				  drawingRect: drawingRect
				     rowIndex: rowIndex];
        }

      [self eauDrawCell: cell
              withFrame: drawingRect
                 inView: outlineView
              textColor: editing ? nil : selectedTextColor];

      if (editing)
        {
          [cell _setInEditing: NO];
          [cell setShowsFirstResponder: NO];
        }
    }
}

@end
