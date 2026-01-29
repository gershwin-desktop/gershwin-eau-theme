#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "EauTitleBarButton.h"
#import "AppearanceMetrics.h"

// Associated object keys for zoom button support
static char hasZoomButtonKey;
static char zoomButtonKey;
static char zoomButtonRectKey;
static char originalFrameKey;  // Store original frame before zoom
@interface GSStandardWindowDecorationView(EauTheme)
- (void) EAUupdateRects;
- (BOOL) hasZoomButton;
- (void) setHasZoomButton:(BOOL)flag;
- (NSButton *) zoomButton;
- (void) setZoomButton:(NSButton *)button;
- (NSRect) zoomButtonRect;
- (void) EAUzoomButtonClicked:(id)sender;
@end

@implementation Eau(GSStandardWindowDecorationView)
- (void) _overrideGSStandardWindowDecorationViewMethod_updateRects {
  GSStandardWindowDecorationView* xself = (GSStandardWindowDecorationView*)self;
  EAULOG(@"GSStandardDecorationView+Eau updateRects");
  [xself EAUupdateRects];
}
@end

@implementation GSStandardWindowDecorationView(EauTheme)
- (void) EAUupdateRects
{
  GSTheme *theme = [GSTheme theme];
  CGFloat viewWidth = [self bounds].size.width;
  CGFloat viewHeight = [self bounds].size.height;

  // Initialize zoom button if not already done
  EAULOG(@"Checking zoom button creation: hasZoomButton=%d, hasTitleBar=%d", [self hasZoomButton], hasTitleBar);
  if (![self hasZoomButton] && hasTitleBar) {
    EAULOG(@"Creating zoom button for window decoration view");
    // Create zoom button using new edge button style
    EauTitleBarButton *zButton = [EauTitleBarButton maximizeButton];
    if (zButton) {
      EAULOG(@"Zoom button created successfully, setting up target and action");
      [self setZoomButton:zButton];
      [zButton setTarget:self];
      [zButton setAction:@selector(EAUzoomButtonClicked:)];
      [zButton setEnabled:YES];
      [self addSubview:zButton];
      [self setHasZoomButton:YES];
      EAULOG(@"Zoom button target: %@, action: %@, window: %@", [zButton target], NSStringFromSelector([zButton action]), window);
    } else {
      EAULOG(@"Failed to create zoom button - zButton is nil");
    }
  }

  if (hasTitleBar)
    {
      CGFloat titleHeight = METRICS_TITLEBAR_HEIGHT;
      titleBarRect = NSMakeRect(0.0, viewHeight - titleHeight,
                            viewWidth, titleHeight);
    }
  if (hasResizeBar)
    {
      resizeBarRect = NSMakeRect(0.0, 0.0, viewWidth, [theme resizebarHeight]);
    }

  // Calculate button positions using edge button layout
  CGFloat titleBarY = viewHeight - METRICS_TITLEBAR_HEIGHT;

  // Close button at left edge, full titlebar height
  if (hasCloseButton)
  {
    closeButtonRect = NSMakeRect(
      0,
      titleBarY,
      METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, METRICS_TITLEBAR_HEIGHT);
    [closeButton setFrame: closeButtonRect];

    // Update to use new button style if it's an EauTitleBarButton
    if ([closeButton isKindOfClass:[EauTitleBarButton class]]) {
      [(EauTitleBarButton *)closeButton setTitleBarButtonType:EauTitleBarButtonTypeClose];
      [(EauTitleBarButton *)closeButton setTitleBarButtonPosition:EauTitleBarButtonPositionLeft];
    }
  }

  // Miniaturize button at BOTTOM half of stacked region on right
  if (hasMiniaturizeButton)
  {
    CGFloat x = viewWidth - METRICS_TITLEBAR_STACKED_REGION_WIDTH;
    CGFloat y = titleBarY;  // Bottom half starts at titlebar Y
    miniaturizeButtonRect = NSMakeRect(
      x, y,
      METRICS_TITLEBAR_STACKED_REGION_WIDTH, METRICS_TITLEBAR_STACKED_BUTTON_HEIGHT);
    [miniaturizeButton setFrame: miniaturizeButtonRect];

    // Update to use new button style if it's an EauTitleBarButton
    if ([miniaturizeButton isKindOfClass:[EauTitleBarButton class]]) {
      [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonType:EauTitleBarButtonTypeMinimize];
      [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonPosition:EauTitleBarButtonPositionRightBottom];
    }
  }

  // Zoom button at TOP half of stacked region on right
  if ([self hasZoomButton])
  {
    CGFloat x = viewWidth - METRICS_TITLEBAR_STACKED_REGION_WIDTH;
    CGFloat y = titleBarY + METRICS_TITLEBAR_STACKED_BUTTON_HEIGHT;  // Top half
    NSRect zoomButtonRect = NSMakeRect(
      x, y,
      METRICS_TITLEBAR_STACKED_REGION_WIDTH, METRICS_TITLEBAR_STACKED_BUTTON_HEIGHT);

    // Store the rect as associated object
    NSValue *rectValue = [NSValue valueWithRect:zoomButtonRect];
    objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Get zoom button and set frame
    NSButton *zoomButton = [self zoomButton];
    if (zoomButton) {
      EAULOG(@"Updating zoom button frame: %@", NSStringFromRect(zoomButtonRect));

      // Ensure target and action are maintained
      [zoomButton setTarget:self];
      [zoomButton setAction:@selector(EAUzoomButtonClicked:)];

      [zoomButton setFrame: zoomButtonRect];
      [zoomButton setEnabled: YES];
      [zoomButton setHidden: NO];
      [zoomButton setNeedsDisplay: YES];

      // Update button properties if it's the new type
      if ([zoomButton isKindOfClass:[EauTitleBarButton class]]) {
        [(EauTitleBarButton *)zoomButton setTitleBarButtonType:EauTitleBarButtonTypeMaximize];
        [(EauTitleBarButton *)zoomButton setTitleBarButtonPosition:EauTitleBarButtonPositionRightTop];
      }

      // Ensure the button is attached
      if ([zoomButton superview] != self)
        {
          [self addSubview: zoomButton];
        }
    }
  }

}

// Zoom button property implementations
- (BOOL) hasZoomButton
{
  NSNumber *hasZoomButtonNum = objc_getAssociatedObject(self, &hasZoomButtonKey);
  return hasZoomButtonNum ? [hasZoomButtonNum boolValue] : NO;
}

- (void) setHasZoomButton:(BOOL)flag
{
  NSNumber *hasZoomButtonNum = [NSNumber numberWithBool:flag];
  objc_setAssociatedObject(self, &hasZoomButtonKey, hasZoomButtonNum, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSButton *) zoomButton
{
  return objc_getAssociatedObject(self, &zoomButtonKey);
}

- (void) setZoomButton:(NSButton *)button
{
  objc_setAssociatedObject(self, &zoomButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSRect) zoomButtonRect
{
  NSValue *rectValue = objc_getAssociatedObject(self, &zoomButtonRectKey);
  return rectValue ? [rectValue rectValue] : NSZeroRect;
}

- (void) EAUzoomButtonClicked:(id)sender
{
  EAULOG(@"*** ZOOM BUTTON CLICKED! sender: %@, window: %@", sender, window);
  EAULOG(@"*** Window isZoomed: %d", [window isZoomed]);

  if ([window isZoomed]) {
    // Window is zoomed, manually restore it to original frame
    EAULOG(@"*** Window is zoomed, attempting manual unzoom");

    NSValue *originalFrameValue = objc_getAssociatedObject(window, &originalFrameKey);
    if (originalFrameValue) {
      NSRect originalFrame = [originalFrameValue rectValue];
      EAULOG(@"*** Restoring window to original frame: %@", NSStringFromRect(originalFrame));
      [window setFrame:originalFrame display:YES animate:NO];

      // Clear the stored frame
      objc_setAssociatedObject(window, &originalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
      EAULOG(@"*** No original frame stored, falling back to performZoom");
      [window performZoom:sender];
    }
  } else {
    // Window is not zoomed, store current frame and zoom it
    EAULOG(@"*** Window is not zoomed, storing frame and zooming");

    // Store current frame before zooming
    NSRect currentFrame = [window frame];
    NSValue *frameValue = [NSValue valueWithRect:currentFrame];
    objc_setAssociatedObject(window, &originalFrameKey, frameValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    EAULOG(@"*** Stored original frame: %@", NSStringFromRect(currentFrame));

    [window zoom:sender];
  }

  EAULOG(@"*** After zoom call - Window isZoomed: %d", [window isZoomed]);
}

@end
