//
// EauTitleBarButton.m
// Eau Theme - Rectangular edge button for titlebar
//

#import "EauTitleBarButton.h"
#import "EauTitleBarButtonCell.h"
#import "AppearanceMetrics.h"

@implementation EauTitleBarButton

+ (Class)cellClass
{
    return [EauTitleBarButtonCell class];
}

+ (instancetype)closeButton
{
    EauTitleBarButton *button = [[EauTitleBarButton alloc] init];
    button.titleBarButtonType = EauTitleBarButtonTypeClose;
    button.titleBarButtonPosition = EauTitleBarButtonPositionLeft;
    [button setTag:NSWindowCloseButton];
    return button;
}

+ (instancetype)minimizeButton
{
    EauTitleBarButton *button = [[EauTitleBarButton alloc] init];
    button.titleBarButtonType = EauTitleBarButtonTypeMinimize;
    button.titleBarButtonPosition = EauTitleBarButtonPositionRightBottom;
    [button setTag:NSWindowMiniaturizeButton];
    return button;
}

+ (instancetype)maximizeButton
{
    EauTitleBarButton *button = [[EauTitleBarButton alloc] init];
    button.titleBarButtonType = EauTitleBarButtonTypeMaximize;
    button.titleBarButtonPosition = EauTitleBarButtonPositionRightTop;
    [button setTag:NSWindowZoomButton];
    return button;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [super setButtonType:NSMomentaryChangeButton];
        [self setBordered:YES];
        [self setRefusesFirstResponder:YES];
        [self setImagePosition:NSNoImage];
        _isWindowActive = YES;
    }
    return self;
}

- (EauTitleBarButtonType)titleBarButtonType
{
    return [(EauTitleBarButtonCell *)[self cell] buttonType];
}

- (void)setTitleBarButtonType:(EauTitleBarButtonType)type
{
    [(EauTitleBarButtonCell *)[self cell] setButtonType:type];
}

- (EauTitleBarButtonPosition)titleBarButtonPosition
{
    return [(EauTitleBarButtonCell *)[self cell] buttonPosition];
}

- (void)setTitleBarButtonPosition:(EauTitleBarButtonPosition)position
{
    [(EauTitleBarButtonCell *)[self cell] setButtonPosition:position];
}

- (BOOL)isWindowActive
{
    return [(EauTitleBarButtonCell *)[self cell] isActive];
}

- (void)setWindowActive:(BOOL)active
{
    _isWindowActive = active;
    [(EauTitleBarButtonCell *)[self cell] setIsActive:active];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped
{
    return NO;
}

@end
