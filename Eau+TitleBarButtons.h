//
// Eau+TitleBarButtons.h
// Eau Theme - Titlebar button rendering for window manager integration
//

#import "Eau.h"
#import "EauTitleBarButtonCell.h"

BOOL EauTitleBarButtonStyleIsOrb(void);

@interface Eau (TitleBarButtons)

// The contract the window manager asks a theme by (see THEMING.md in
// gershwin-windowmanager): Eau lays out and draws its own titlebar buttons
// when it is set to the orb style, and leaves them to the window manager
// otherwise.
- (BOOL)drawsTitlebarButtons;
- (NSRect)titlebarButtonRectForButton:(NSInteger)button
                        titlebarWidth:(CGFloat)width
                            styleMask:(NSUInteger)styleMask;

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
- (NSColor *)iconColorForActive:(BOOL)active highlighted:(BOOL)highlighted;

// Orb button drawing
- (void)drawOrbInRect:(NSRect)rect
        withBaseColor:(NSColor *)baseColor
               active:(BOOL)active
              hovered:(BOOL)hovered;

@end
