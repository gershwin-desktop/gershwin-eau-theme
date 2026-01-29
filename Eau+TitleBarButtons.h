//
// Eau+TitleBarButtons.h
// Eau Theme - Titlebar button rendering for window manager integration
//

#import "Eau.h"
#import "EauTitleBarButtonCell.h"

@interface Eau (TitleBarButtons)

// Geometry queries for window manager
- (CGFloat)titlebarHeight;
- (NSRect)closeButtonRectForTitlebarWidth:(CGFloat)width;
- (NSRect)minimizeButtonRectForTitlebarWidth:(CGFloat)width;
- (NSRect)maximizeButtonRectForTitlebarWidth:(CGFloat)width;
- (NSRect)rightButtonRegionRectForTitlebarWidth:(CGFloat)width;

// Drawing methods for window manager
- (void)drawTitlebarInRect:(NSRect)rect withTitle:(NSString *)title active:(BOOL)active;
- (void)drawCloseButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active;
- (void)drawMinimizeButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active;
- (void)drawMaximizeButtonInRect:(NSRect)rect state:(GSThemeControlState)state active:(BOOL)active;

// Icon drawing helpers
- (void)drawCloseIconInRect:(NSRect)rect withColor:(NSColor *)color;
- (void)drawMinimizeIconInRect:(NSRect)rect withColor:(NSColor *)color;
- (void)drawMaximizeIconInRect:(NSRect)rect withColor:(NSColor *)color;

@end
