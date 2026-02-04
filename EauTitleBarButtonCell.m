//
// EauTitleBarButtonCell.m
// Eau Theme - Rectangular edge buttons for titlebar
//

#import <AppKit/AppKit.h>
#import "EauTitleBarButtonCell.h"
#import "AppearanceMetrics.h"
#import "Eau.h"

@implementation EauTitleBarButtonCell

@synthesize buttonType = _buttonType;
@synthesize buttonPosition = _buttonPosition;
@synthesize isActive = _isActive;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _buttonType = EauTitleBarButtonTypeClose;
        _buttonPosition = EauTitleBarButtonPositionLeft;
        _isActive = YES;
    }
    return self;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if (NSIsEmptyRect(cellFrame))
        return;

    [self drawButtonInRect:cellFrame];
    [self drawIconInRect:cellFrame];
}

- (void)drawButtonInRect:(NSRect)frame
{
    // Get button gradient colors
    NSColor *gradientColor1;
    NSColor *gradientColor2;

    // Check if button is hovered (highlighted)
    BOOL isHovered = _cell.is_highlighted;

    if (isHovered) {
        // Hover colors - traffic light colors (apply to ALL windows, active and inactive)
        switch (_buttonType) {
            case EauTitleBarButtonTypeClose:  // Red
                gradientColor1 = [NSColor colorWithCalibratedRed:0.95 green:0.45 blue:0.42 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.85 green:0.30 blue:0.27 alpha:1];
                break;
            case EauTitleBarButtonTypeMinimize:  // Yellow
                gradientColor1 = [NSColor colorWithCalibratedRed:0.95 green:0.75 blue:0.25 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.85 green:0.65 blue:0.15 alpha:1];
                break;
            case EauTitleBarButtonTypeMaximize:  // Green
                gradientColor1 = [NSColor colorWithCalibratedRed:0.35 green:0.78 blue:0.35 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.25 green:0.68 blue:0.25 alpha:1];
                break;
            default:
                // Fallback to gray
                gradientColor1 = [NSColor colorWithCalibratedRed:0.65 green:0.65 blue:0.65 alpha:1];
                gradientColor2 = [NSColor colorWithCalibratedRed:0.45 green:0.45 blue:0.45 alpha:1];
                break;
        }
    } else if (_isActive) {
        // Active window - #C2C2C2 average (0.76) with subtle gradient
        gradientColor1 = [NSColor colorWithCalibratedRed:0.82 green:0.82 blue:0.82 alpha:1];  // #D1D1D1
        gradientColor2 = [NSColor colorWithCalibratedRed:0.70 green:0.70 blue:0.70 alpha:1];  // #B3B3B3
    } else {
        // Inactive window - slightly lighter/washed out
        gradientColor1 = [NSColor colorWithCalibratedRed:0.85 green:0.85 blue:0.85 alpha:1];
        gradientColor2 = [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1];
    }

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:gradientColor1
                                                         endingColor:gradientColor2];

    NSColor *borderColor = [Eau controlStrokeColor];

    // Top border color - matches titlebar top edge (slightly lighter for visual trick)
    NSColor *topBorderColor = [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.5 alpha:1.0];

    // Create path with rounded corner only on inner edge
    NSBezierPath *path = [self buttonPathForRect:frame];

    // Fill with gradient
    [gradient drawInBezierPath:path angle:-90];

    // Draw inner highlight near top (gives raised 3D look)
    NSColor *highlightColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.35];
    NSBezierPath *highlightPath = [NSBezierPath bezierPath];
    CGFloat highlightY = NSMaxY(frame) - 2.5;
    [highlightPath moveToPoint:NSMakePoint(NSMinX(frame) + 1, highlightY)];
    [highlightPath lineToPoint:NSMakePoint(NSMaxX(frame) - 1, highlightY)];
    [highlightColor setStroke];
    [highlightPath setLineWidth:1.0];
    [highlightPath stroke];

    // Draw inner shadow near bottom (gives depth)
    NSColor *shadowColor = [NSColor colorWithCalibratedWhite:0.0 alpha:0.15];
    NSBezierPath *shadowPath = [NSBezierPath bezierPath];
    CGFloat shadowY = NSMinY(frame) + 1.5;
    [shadowPath moveToPoint:NSMakePoint(NSMinX(frame) + 1, shadowY)];
    [shadowPath lineToPoint:NSMakePoint(NSMaxX(frame) - 1, shadowY)];
    [shadowColor setStroke];
    [shadowPath setLineWidth:1.0];
    [shadowPath stroke];

    // Stroke border
    [borderColor setStroke];
    [path setLineWidth:1.0];
    [path stroke];

    // Draw top border line (replicates titlebar top edge on buttons)
    NSBezierPath *topLine = [NSBezierPath bezierPath];
    CGFloat radius = METRICS_TITLEBAR_BUTTON_INNER_RADIUS;
    if (_buttonPosition == EauTitleBarButtonPositionLeft) {
        // Close button: line from after top-left arc to right edge
        [topLine moveToPoint:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame) - 0.5)];
        [topLine lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame) - 0.5)];
        [topBorderColor setStroke];
        [topLine setLineWidth:1.0];
        [topLine stroke];
    } else if (_buttonPosition == EauTitleBarButtonPositionRightTop) {
        // Zoom button (top of stack): line from left edge to before top-right arc
        [topLine moveToPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame) - 0.5)];
        [topLine lineToPoint:NSMakePoint(NSMaxX(frame) - radius, NSMaxY(frame) - 0.5)];
        [topBorderColor setStroke];
        [topLine setLineWidth:1.0];
        [topLine stroke];
    }
    // RightBottom (minimize) has no top border line - it's interior

    // Draw horizontal divider between stacked buttons (at bottom of zoom button)
    if (_buttonPosition == EauTitleBarButtonPositionRightTop) {
        NSBezierPath *divider = [NSBezierPath bezierPath];
        [divider moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame) + 0.5)];
        [divider lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame) + 0.5)];
        [borderColor setStroke];
        [divider setLineWidth:1.0];
        [divider stroke];
    }
}

- (NSBezierPath *)buttonPathForRect:(NSRect)frame
{
    CGFloat radius = METRICS_TITLEBAR_BUTTON_INNER_RADIUS;
    NSBezierPath *path = [NSBezierPath bezierPath];

    switch (_buttonPosition) {
        case EauTitleBarButtonPositionLeft:
            // Close button: ONLY top-left corner rounded, inner edge (right) is straight
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];  // bottom-left
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];  // bottom-right (straight)
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame))];  // top-right (straight inner edge)
            [path lineToPoint:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame))];  // to top-left arc start
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMinX(frame) + radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:90
                                           endAngle:180];  // top-left corner
            [path closePath];
            break;

        case EauTitleBarButtonPositionRightTop:
            // Zoom button (top of stack): ONLY top-right corner rounded
            [path moveToPoint:NSMakePoint(NSMinX(frame), NSMinY(frame))];  // bottom-left
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMinY(frame))];  // bottom-right
            [path lineToPoint:NSMakePoint(NSMaxX(frame), NSMaxY(frame) - radius)];  // up right edge to arc
            [path appendBezierPathWithArcWithCenter:NSMakePoint(NSMaxX(frame) - radius, NSMaxY(frame) - radius)
                                             radius:radius
                                         startAngle:0
                                           endAngle:90];  // top-right corner
            [path lineToPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame))];  // straight left edge
            [path closePath];
            break;

        case EauTitleBarButtonPositionRightBottom:
            // Minimize button (bottom of stack): NO rounding (interior button)
            [path appendBezierPathWithRect:frame];
            break;
    }

    return path;
}

- (void)drawIconInRect:(NSRect)frame
{
    // Don't draw icons on inactive windows
    if (!_isActive) {
        return;
    }

    // Use appropriate icon insets based on button position
    NSRect iconRect;
    if (_buttonPosition == EauTitleBarButtonPositionLeft) {
        iconRect = NSInsetRect(frame, METRICS_TITLEBAR_ICON_INSET, METRICS_TITLEBAR_ICON_INSET);
    } else {
        // Stacked buttons: smaller vertical inset for half-height buttons
        CGFloat hInset = 8.0;
        CGFloat vInset = 2.0;
        iconRect = NSInsetRect(frame, hInset, vInset);
    }

    // Make icon rect square by adding extra horizontal inset if needed
    CGFloat extraHInset = (NSWidth(iconRect) - NSHeight(iconRect)) / 2.0;
    if (extraHInset > 0) {
        iconRect = NSInsetRect(iconRect, extraHInset, 0);
    }

    // Darker icon color for active windows (0.20)
    NSColor *iconColor = [NSColor colorWithCalibratedRed:0.20 green:0.20 blue:0.20 alpha:1.0];

    if (_cell.is_highlighted) {
        iconColor = [iconColor shadowWithLevel:0.2];
    }

    [iconColor setStroke];

    // Detect stacked button (small height) - use bolder/bigger icon for +/-
    BOOL isStacked = (NSHeight(iconRect) < 10);

    NSBezierPath *iconPath = [NSBezierPath bezierPath];
    [iconPath setLineCapStyle:NSRoundLineCapStyle];

    switch (_buttonType) {
        case EauTitleBarButtonTypeClose: {
            // Lowercase x style - shorter strokes, more square
            [iconPath setLineWidth:METRICS_TITLEBAR_ICON_STROKE];
            CGFloat inset = NSWidth(iconRect) * 0.15;
            [iconPath moveToPoint:NSMakePoint(NSMinX(iconRect) + inset, NSMinY(iconRect) + inset)];
            [iconPath lineToPoint:NSMakePoint(NSMaxX(iconRect) - inset, NSMaxY(iconRect) - inset)];
            [iconPath moveToPoint:NSMakePoint(NSMaxX(iconRect) - inset, NSMinY(iconRect) + inset)];
            [iconPath lineToPoint:NSMakePoint(NSMinX(iconRect) + inset, NSMaxY(iconRect) - inset)];
            break;
        }

        case EauTitleBarButtonTypeMinimize: {
            // Horizontal line (minus symbol) - bolder for stacked
            CGFloat strokeWidth = isStacked ? 2.0 : METRICS_TITLEBAR_ICON_STROKE;
            CGFloat insetFactor = isStacked ? 0.05 : 0.15;
            [iconPath setLineWidth:strokeWidth];
            CGFloat inset = NSWidth(iconRect) * insetFactor;
            CGFloat midY = NSMidY(iconRect);
            [iconPath moveToPoint:NSMakePoint(NSMinX(iconRect) + inset, midY)];
            [iconPath lineToPoint:NSMakePoint(NSMaxX(iconRect) - inset, midY)];
            break;
        }

        case EauTitleBarButtonTypeMaximize: {
            // Plus symbol - bolder for stacked
            CGFloat strokeWidth = isStacked ? 2.0 : METRICS_TITLEBAR_ICON_STROKE;
            CGFloat insetFactor = isStacked ? 0.05 : 0.15;
            [iconPath setLineWidth:strokeWidth];
            CGFloat inset = NSWidth(iconRect) * insetFactor;
            CGFloat midX = NSMidX(iconRect);
            CGFloat midY = NSMidY(iconRect);
            // Horizontal line
            [iconPath moveToPoint:NSMakePoint(NSMinX(iconRect) + inset, midY)];
            [iconPath lineToPoint:NSMakePoint(NSMaxX(iconRect) - inset, midY)];
            // Vertical line
            [iconPath moveToPoint:NSMakePoint(midX, NSMinY(iconRect) + inset)];
            [iconPath lineToPoint:NSMakePoint(midX, NSMaxY(iconRect) - inset)];
            break;
        }
    }

    [iconPath stroke];
}

@end
