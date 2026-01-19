#include "Eau.h"
#include "EauScrollerKnobCell.h"
#include "EauScrollerKnobSlotCell.h"
#include "EauScrollerArrowCell.h"

@interface Eau(EauScroller)

@end

@implementation Eau(EauScroller)

/* NSScroller themeing. */

- (NSButtonCell*) cellForScrollerArrow: (NSScrollerArrow)arrow
			    horizontal: (BOOL)horizontal
{
  EauScrollerArrowCell	*cell;
  NSString	*name;

  cell = [EauScrollerArrowCell new];
  [cell setBezelStyle: NSRoundRectBezelStyle];
  if (horizontal)
    {
      if (arrow == NSScrollerDecrementArrow)
	{
	  [cell setHighlightsBy:
	    NSChangeBackgroundCellMask | NSContentsCellMask];
	  [cell setImage: [NSImage imageNamed: @"common_ArrowLeft"]];
	  [cell setImagePosition: NSImageOnly];
          name = GSScrollerLeftArrow;
    [cell setArrowType: EauScrollerArrowLeft];
	}
      else
	{
	  [cell setHighlightsBy:
	    NSChangeBackgroundCellMask | NSContentsCellMask];
      [cell setImage: [NSImage imageNamed: @"common_ArrowRight"]];
      [cell setImagePosition: NSImageOnly];
      name = GSScrollerRightArrow;
    [cell setArrowType: EauScrollerArrowRight];
	}
    }
  else
    {
      if (arrow == NSScrollerDecrementArrow)
	{
	  [cell setHighlightsBy:
	    NSChangeBackgroundCellMask | NSContentsCellMask];
      [cell setImage: [NSImage imageNamed: @"common_ArrowUp"]];
      [cell setImagePosition: NSImageOnly];
      name = GSScrollerUpArrow;
    [cell setArrowType: EauScrollerArrowUp];
	}
      else
	{
	  [cell setHighlightsBy:
	    NSChangeBackgroundCellMask | NSContentsCellMask];
	  [cell setImage: [NSImage imageNamed: @"common_ArrowDown"]];
	  [cell setImagePosition: NSImageOnly];
          name = GSScrollerDownArrow;
    [cell setArrowType: EauScrollerArrowDown];
	}
    }
  [self setName: name forElement: cell temporary: YES];
  return cell;
}

- (NSCell*) cellForScrollerKnob: (BOOL)horizontal
{
  NSButtonCell	*cell;

  cell = [EauScrollerKnobCell new];
  [cell setButtonType: NSMomentaryChangeButton];
  [cell setBezelStyle: NSRoundedBezelStyle];
  [cell setImagePosition: NSImageOnly];

  [cell setTitle: @""];
  if (horizontal)
    {
      [self setName: GSScrollerHorizontalKnob forElement: cell temporary: YES];
    }
  else
    {
      [self setName: GSScrollerVerticalKnob forElement: cell temporary: YES];
    }
  return cell;
}

- (NSCell*) cellForScrollerKnobSlot: (BOOL)horizontal
{
  // TS: unused
  // GSDrawTiles   		*tiles;
  EauScrollerKnobSlotCell	*cell;
  NSColor			*color;
  NSString      		*name;

  if (horizontal)
    {
      name = GSScrollerHorizontalSlot;
    }
  else
    {
      name = GSScrollerVerticalSlot;
    }

  // TS: unused
  // tiles = [self tilesNamed: name state: GSThemeNormalState];
  color = [self colorNamed: name state: GSThemeNormalState];

  cell = [EauScrollerKnobSlotCell new];
  [cell setBordered: false];
  [cell setTitle: nil];
  [cell setHorizontal: horizontal];
  [self setName: name forElement: cell temporary: YES];

  if (color == nil)
    {
      color = [NSColor scrollBarColor];
    }
  [cell setBackgroundColor: color];
  return cell;
}
// REMEMBER THIS SETTING
- (float) defaultScrollerWidth
{
  return 16.0;
}

- (BOOL) scrollViewUseBottomCorner
{
  // NO = leave gap at corner where h/v scrollers meet (for resize grip)
  // YES = scrollers extend into corner (no gap)
  return NO;
}

- (BOOL) scrollViewScrollersOverlapBorders
{
  return YES;
}

- (BOOL) scrollViewShouldAutohideScrollers
{
  return YES;
}

- (BOOL) scrollerArrowsSameEndForScroller: (NSScroller *)aScroller
{
  // NO = split arrows (one at each end of scroller)
  // YES = both arrows grouped at one end
  return NO;
}

@end
