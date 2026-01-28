//
// EauTitleBarButton.h
// Eau Theme - Rectangular edge button for titlebar
//

#import <AppKit/NSButton.h>
#import "EauTitleBarButtonCell.h"

@interface EauTitleBarButton : NSButton

@property (nonatomic, assign) EauTitleBarButtonType titleBarButtonType;
@property (nonatomic, assign) EauTitleBarButtonPosition titleBarButtonPosition;
@property (nonatomic, assign) BOOL isWindowActive;

+ (instancetype)closeButton;
+ (instancetype)minimizeButton;
+ (instancetype)maximizeButton;

- (void)setWindowActive:(BOOL)active;

@end
