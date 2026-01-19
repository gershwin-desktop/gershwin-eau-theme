#import <AppKit/NSButtonCell.h>



@interface EauWindowButtonCell : NSButtonCell
{
  NSColor * baseColor;
}
- (void) drawBallWithRect: (NSRect)frame;
- (void) drawWithFrame: (NSRect)cellFrame inView: (NSView*)controlView;
@property (strong) NSColor * baseColor;
@end
