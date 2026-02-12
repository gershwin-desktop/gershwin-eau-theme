#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "EauTitleBarButton.h"
#import "EauWindowButton.h"
#import "Eau+TitleBarButtons.h"
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
  BOOL isOrb = EauTitleBarButtonStyleIsOrb();

  // Initialize zoom button if not already done (only for resizable windows)
  NSUInteger styleMask = [[self window] styleMask];
  EAULOG(@"Checking zoom button creation: hasZoomButton=%d, hasTitleBar=%d, resizable=%d", [self hasZoomButton], hasTitleBar, (int)(styleMask & NSResizableWindowMask));
  if (![self hasZoomButton] && hasTitleBar && (styleMask & NSResizableWindowMask)) {
    EAULOG(@"Creating zoom button for window decoration view");
    NSButton *zButton;
    if (isOrb) {
      EauWindowButton *orbButton = [[EauWindowButton alloc] init];
      [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.322 green:0.778 blue:0.244 alpha:1]];
      [orbButton setRefusesFirstResponder: YES];
      [orbButton setButtonType: NSMomentaryChangeButton];
      [orbButton setImagePosition: NSImageOnly];
      [orbButton setBordered: YES];
      [orbButton setTag: NSWindowZoomButton];
      [orbButton setImage: [NSImage imageNamed: @"common_Zoom"]];
      [orbButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
      zButton = orbButton;
    } else {
      zButton = [EauTitleBarButton maximizeButton];
    }
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

  CGFloat titleBarY = viewHeight - METRICS_TITLEBAR_HEIGHT;

  if (isOrb) {
    // Orb style: all 3 buttons on left, 15x15, vertically centered
    CGFloat buttonY = titleBarY + (METRICS_TITLEBAR_HEIGHT - METRICS_TITLEBAR_ORB_BUTTON_SIZE) / 2.0;
    CGFloat x = METRICS_TITLEBAR_ORB_PADDING_LEFT;

    if (hasCloseButton)
    {
      closeButtonRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);
      [closeButton setFrame: closeButtonRect];
      x += METRICS_TITLEBAR_ORB_BUTTON_SIZE + METRICS_TITLEBAR_ORB_BUTTON_SPACING;
    }

    if (hasMiniaturizeButton)
    {
      miniaturizeButtonRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);
      [miniaturizeButton setFrame: miniaturizeButtonRect];
      x += METRICS_TITLEBAR_ORB_BUTTON_SIZE + METRICS_TITLEBAR_ORB_BUTTON_SPACING;
    }

    if ([self hasZoomButton])
    {
      NSRect zoomRect = NSMakeRect(x, buttonY,
        METRICS_TITLEBAR_ORB_BUTTON_SIZE, METRICS_TITLEBAR_ORB_BUTTON_SIZE);

      NSValue *rectValue = [NSValue valueWithRect:zoomRect];
      objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      NSButton *zoomButton = [self zoomButton];
      if (zoomButton) {
        [zoomButton setTarget:self];
        [zoomButton setAction:@selector(EAUzoomButtonClicked:)];
        [zoomButton setFrame: zoomRect];
        [zoomButton setEnabled: YES];
        [zoomButton setHidden: NO];
        [zoomButton setNeedsDisplay: YES];
        if ([zoomButton superview] != self) {
          [self addSubview: zoomButton];
        }
      }
    }
  } else {
    // Edge style: close on left, minimize+maximize on right

    // Close button at left edge, full titlebar height
    if (hasCloseButton)
    {
      closeButtonRect = NSMakeRect(
        0,
        titleBarY,
        METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, METRICS_TITLEBAR_HEIGHT);
      [closeButton setFrame: closeButtonRect];

      if ([closeButton isKindOfClass:[EauTitleBarButton class]]) {
        [(EauTitleBarButton *)closeButton setTitleBarButtonType:EauTitleBarButtonTypeClose];
        [(EauTitleBarButton *)closeButton setTitleBarButtonPosition:EauTitleBarButtonPositionLeft];
      }
    }

    // Miniaturize button - position depends on whether zoom button exists
    if (hasMiniaturizeButton)
    {
      CGFloat x;
      EauTitleBarButtonPosition position;
      if ([self hasZoomButton]) {
        x = viewWidth - METRICS_TITLEBAR_RIGHT_REGION_WIDTH;
        position = EauTitleBarButtonPositionRightInner;
      } else {
        x = viewWidth - METRICS_TITLEBAR_EDGE_BUTTON_WIDTH;
        position = EauTitleBarButtonPositionRightOuter;
      }
      miniaturizeButtonRect = NSMakeRect(
        x, titleBarY,
        METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, METRICS_TITLEBAR_HEIGHT);
      [miniaturizeButton setFrame: miniaturizeButtonRect];

      if ([miniaturizeButton isKindOfClass:[EauTitleBarButton class]]) {
        [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonType:EauTitleBarButtonTypeMinimize];
        [(EauTitleBarButton *)miniaturizeButton setTitleBarButtonPosition:position];
      }
    }

    // Zoom button - outer (rightmost) of two side-by-side buttons on right
    if ([self hasZoomButton])
    {
      CGFloat x = viewWidth - METRICS_TITLEBAR_EDGE_BUTTON_WIDTH;
      NSRect zoomButtonRect = NSMakeRect(
        x, titleBarY,
        METRICS_TITLEBAR_EDGE_BUTTON_WIDTH, METRICS_TITLEBAR_HEIGHT);

      NSValue *rectValue = [NSValue valueWithRect:zoomButtonRect];
      objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

      NSButton *zoomButton = [self zoomButton];
      if (zoomButton) {
        EAULOG(@"Updating zoom button frame: %@", NSStringFromRect(zoomButtonRect));

        [zoomButton setTarget:self];
        [zoomButton setAction:@selector(EAUzoomButtonClicked:)];
        [zoomButton setFrame: zoomButtonRect];
        [zoomButton setEnabled: YES];
        [zoomButton setHidden: NO];
        [zoomButton setNeedsDisplay: YES];

        if ([zoomButton isKindOfClass:[EauTitleBarButton class]]) {
          [(EauTitleBarButton *)zoomButton setTitleBarButtonType:EauTitleBarButtonTypeMaximize];
          [(EauTitleBarButton *)zoomButton setTitleBarButtonPosition:EauTitleBarButtonPositionRightOuter];
        }

        if ([zoomButton superview] != self) {
          [self addSubview: zoomButton];
        }
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
