#import <AppKit/NSView.h>

/**
 * A view that draws the grow box (resize grip) in the bottom-right corner
 * of resizable windows. Added automatically by the theme to windows that
 * have NSResizableWindowMask in their style mask.
 *
 * A window whose bottom edge rises towards the right side (a shaped,
 * curved outline) implements -resizeIndicatorBottomInset, returning in
 * points how far above the corner its edge ends there; the grip sits that
 * much higher, inside the window.
 */
@interface EauGrowBoxView : NSView
+ (void)addToWindow:(NSWindow *)window;
+ (void)raiseInWindow:(NSWindow *)window;
+ (void)removeFromWindow:(NSWindow *)window;
@end

@interface NSWindow (EauResizeIndicatorInset)
- (CGFloat)resizeIndicatorBottomInset;
@end
