/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauTestFormBuilder.h"
#import "AppearanceMetrics.h"

static const CGFloat EauTestLabelWidth = 110.0;
static const CGFloat EauTestLabelHeight = 17.0;

@implementation EauTestFormBuilder
{
  NSView *_view;
  CGFloat _top;
}

- (instancetype)initWithView:(NSView *)view
{
  if ((self = [super init]) != nil)
    {
      _view = view;
      _top = NSHeight([view bounds]) - METRICS_CONTENT_TOP_MARGIN;
    }
  return self;
}

- (void)addRowWithLabel:(NSString *)label controls:(NSArray *)controls
{
  CGFloat rowHeight = EauTestLabelHeight;
  for (NSView *control in controls)
    rowHeight = MAX(rowHeight, NSHeight([control frame]));
  CGFloat bottom = _top - rowHeight;

  NSTextField *labelField = [[NSTextField alloc] initWithFrame:
    NSMakeRect(METRICS_CONTENT_SIDE_MARGIN,
               bottom + floor((rowHeight - EauTestLabelHeight) / 2.0),
               EauTestLabelWidth, EauTestLabelHeight)];
  [labelField setStringValue: label];
  [labelField setEditable: NO];
  [labelField setSelectable: NO];
  [labelField setBezeled: NO];
  [labelField setDrawsBackground: NO];
  [labelField setAlignment: NSRightTextAlignment];
  /* The panes live in a resizable window; y-up coordinates would otherwise
   * keep rows glued to the bottom edge while the window grows. */
  [labelField setAutoresizingMask: NSViewMinYMargin];
  [_view addSubview: labelField];

  CGFloat x = METRICS_CONTENT_SIDE_MARGIN + EauTestLabelWidth + METRICS_SPACE_8;
  for (NSView *control in controls)
    {
      NSRect frame = [control frame];
      frame.origin = NSMakePoint(x,
        bottom + floor((rowHeight - NSHeight(frame)) / 2.0));
      [control setFrame: frame];
      [control setAutoresizingMask: NSViewMinYMargin];
      [_view addSubview: control];
      x = NSMaxX(frame) + METRICS_BUTTON_HORIZ_INTERSPACE;
    }

  _top = bottom - METRICS_SPACE_8;
}

@end
