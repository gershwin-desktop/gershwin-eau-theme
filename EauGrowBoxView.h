#import <AppKit/NSView.h>

/**
 * A view that draws the grow box (resize grip) in the bottom-right corner
 * of resizable windows. Added automatically by the theme to windows that
 * have NSResizableWindowMask in their style mask.
 */
@interface EauGrowBoxView : NSView
+ (void)addToWindow:(NSWindow *)window;
+ (void)raiseInWindow:(NSWindow *)window;
+ (void)removeFromWindow:(NSWindow *)window;
@end
