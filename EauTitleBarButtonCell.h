//
// EauTitleBarButtonCell.h
// Eau Theme - Rectangular edge buttons for titlebar
//

#import <AppKit/NSButtonCell.h>

// Button types for titlebar edge buttons
typedef NS_ENUM(NSInteger, EauTitleBarButtonType) {
    EauTitleBarButtonTypeClose = 0,
    EauTitleBarButtonTypeMinimize,
    EauTitleBarButtonTypeMaximize
};

// Position in the titlebar
typedef NS_ENUM(NSInteger, EauTitleBarButtonPosition) {
    EauTitleBarButtonPositionLeft = 0,      // Close button - left edge
    EauTitleBarButtonPositionRightTop,      // Zoom (+) - top of stacked region
    EauTitleBarButtonPositionRightBottom    // Minimize (-) - bottom of stacked region
};

@interface EauTitleBarButtonCell : NSButtonCell
{
    EauTitleBarButtonType _buttonType;
    EauTitleBarButtonPosition _buttonPosition;
    BOOL _isActive;  // Window active state
}

@property (nonatomic, assign) EauTitleBarButtonType buttonType;
@property (nonatomic, assign) EauTitleBarButtonPosition buttonPosition;
@property (nonatomic, assign) BOOL isActive;

- (void)drawButtonInRect:(NSRect)frame;
- (void)drawIconInRect:(NSRect)frame;

@end
