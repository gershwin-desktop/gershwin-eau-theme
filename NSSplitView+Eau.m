#import "Eau.h"
#import <AppKit/AppKit.h>

@interface NSSplitView (EauTheme)
- (CGFloat) EAUdividerThickness;
- (void) EAUdrawDividerInRect: (NSRect)rect;
@end

@implementation Eau(NSSplitView)

- (CGFloat) _overrideNSSplitViewMethod_dividerThickness
{
  NSSplitView *xself = (NSSplitView *)self;
  return [xself EAUdividerThickness];
}

- (void) _overrideNSSplitViewMethod_drawDividerInRect: (NSRect)rect
{
  NSSplitView *xself = (NSSplitView *)self;
  [xself EAUdrawDividerInRect: rect];
}

@end

@implementation NSSplitView (EauTheme)

- (CGFloat) EAUdividerThickness
{
  return 1.0;
}

- (void) EAUdrawDividerInRect: (NSRect)rect
{
  [[NSColor colorWithCalibratedRed: 0.8 green: 0.8 blue: 0.8 alpha: 1.0] setFill];
  NSRectFill(rect);
}

@end
