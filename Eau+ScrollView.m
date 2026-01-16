#import "Eau.h"
#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>

@interface Eau(EauScrollView)
@end

@implementation Eau(EauScrollView)

- (void) drawScrollViewRect: (NSRect)rect
                     inView: (NSView *)view
{
  (void)rect;
  NSScrollView *scrollView = (NSScrollView *)view;
  NSRect bounds = [view bounds];

  [[NSColor windowBackgroundColor] setFill];
  NSRectFill(bounds);

  if (![scrollView isKindOfClass:[NSScrollView class]])
    return;

  switch ([scrollView borderType])
    {
      case NSNoBorder:
        break;
      case NSLineBorder:
        [[Eau controlStrokeColor] setStroke];
        NSFrameRect(bounds);
        break;
      case NSBezelBorder:
      case NSGrooveBorder:
        {
          NSRect borderRect = NSInsetRect(bounds, 0.5, 0.5);
          [[Eau controlStrokeColor] setStroke];
          NSFrameRectWithWidth(borderRect, 1.0);
          break;
        }
      default:
        break;
    }
}

@end
