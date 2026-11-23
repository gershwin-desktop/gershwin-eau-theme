#import <AppKit/NSView.h>

/**
 * A view that draws the grow box (resize grip) in the bottom-right corner
 * of resizable windows. Added automatically by the theme to windows that
 * have NSResizableWindowMask in their style mask.
 */
@interface EauGrowBoxView : NSView
+ (void)addToWindow:(NSWindow *)window;
/* For a window whose frame has settled on device pixels already (a panel
 * that was a sheet): sizes the grip in whole device pixels, as autoresizing
 * leaves one added before the window's first frame. */
+ (void)addToSettledWindow:(NSWindow *)window;
+ (void)raiseInWindow:(NSWindow *)window;
+ (void)removeFromWindow:(NSWindow *)window;
@end
