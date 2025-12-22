#import <GNUstepGUI/GSWindowDecorationView.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import "Rik.h"
#import "RikWindowButton.h"

#define TITLEBAR_BUTTON_SIZE 15
#define TITLEBAR_PADDING_LEFT 10.5
#define TITLEBAR_PADDING_RIGHT 10.5
#define TITLEBAR_PADDING_TOP 5.5

// Associated object keys for zoom button support
static char hasZoomButtonKey;
static char zoomButtonKey;
static char zoomButtonRectKey;
static char originalFrameKey;  // Store original frame before zoom
@interface GSStandardWindowDecorationView(RikTheme)
- (void) RIKupdateRects;
- (BOOL) hasZoomButton;
- (void) setHasZoomButton:(BOOL)flag;
- (NSButton *) zoomButton;
- (void) setZoomButton:(NSButton *)button;
- (NSRect) zoomButtonRect;
- (void) RIKzoomButtonClicked:(id)sender;
@end

@implementation Rik(GSStandardWindowDecorationView)
- (void) _overrideGSStandardWindowDecorationViewMethod_updateRects {
  GSStandardWindowDecorationView* xself = (GSStandardWindowDecorationView*)self;
  RIKLOG(@"GSStandardDecorationView+Rik updateRects");
  [xself RIKupdateRects];
}
@end

@implementation GSStandardWindowDecorationView(RikTheme)
- (void) RIKupdateRects
{
  GSTheme *theme = [GSTheme theme];

  // Initialize zoom button if not already done
  RIKLOG(@"Checking zoom button creation: hasZoomButton=%d, hasTitleBar=%d", [self hasZoomButton], hasTitleBar);
  if (![self hasZoomButton] && hasTitleBar) {
    RIKLOG(@"Creating zoom button for window decoration view");
    // Create zoom button directly like in NSWindow+Rik.m
    RikWindowButton *zButton = [[RikWindowButton alloc] init];
    [zButton setBaseColor: [NSColor colorWithCalibratedRed: 0.322 green: 0.778 blue: 0.244 alpha: 1]];
    [zButton setImage: [NSImage imageNamed: @"common_Zoom"]];
    [zButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
    [zButton setRefusesFirstResponder: YES];
    [zButton setButtonType: NSMomentaryChangeButton];
    [zButton setImagePosition: NSImageOnly];
    [zButton setBordered: YES];
    [zButton setTag: NSWindowZoomButton];
    if (zButton) {
      RIKLOG(@"Zoom button created successfully, setting up target and action");
      [self setZoomButton:zButton];
      [zButton setTarget:self];  // Target this decoration view instead of window
      [zButton setAction:@selector(RIKzoomButtonClicked:)];  // Use our custom action
      [zButton setEnabled:YES];  // Ensure it starts enabled
      [self addSubview:zButton];
      [self setHasZoomButton:YES];  // Only set flag AFTER successful creation
      RIKLOG(@"Zoom button target: %@, action: %@, window: %@", [zButton target], NSStringFromSelector([zButton action]), window);
    } else {
      RIKLOG(@"Failed to create zoom button - zButton is nil");
    }
  }

  if (hasTitleBar)
    {
      CGFloat titleHeight = [theme titlebarHeight];
      titleBarRect = NSMakeRect(0.0, [self bounds].size.height - titleHeight,
                            [self bounds].size.width, titleHeight);
    }
  if (hasResizeBar)
    {
      resizeBarRect = NSMakeRect(0.0, 0.0, [self bounds].size.width, [theme resizebarHeight]);
    }
  if (hasCloseButton)
  {
    closeButtonRect = NSMakeRect(
      TITLEBAR_PADDING_LEFT,
      [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
      TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);
    [closeButton setFrame: closeButtonRect];
  }

  if (hasMiniaturizeButton)
  {
    miniaturizeButtonRect = NSMakeRect(
      TITLEBAR_PADDING_LEFT + TITLEBAR_BUTTON_SIZE + 4, // 4px padding between buttons
      [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
      TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);
    [miniaturizeButton setFrame: miniaturizeButtonRect];
  }

  if ([self hasZoomButton])
  {
    NSRect zoomButtonRect = NSMakeRect(
      TITLEBAR_PADDING_LEFT + (TITLEBAR_BUTTON_SIZE + 4) * 2, // After miniaturize button
      [self bounds].size.height - TITLEBAR_BUTTON_SIZE - TITLEBAR_PADDING_TOP,
      TITLEBAR_BUTTON_SIZE, TITLEBAR_BUTTON_SIZE);

    // Store the rect as associated object
    NSValue *rectValue = [NSValue valueWithRect:zoomButtonRect];
    objc_setAssociatedObject(self, &zoomButtonRectKey, rectValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Get zoom button and set frame
    NSButton *zoomButton = [self zoomButton];
    if (zoomButton) {
      RIKLOG(@"Updating zoom button frame: %@", NSStringFromRect(zoomButtonRect));
      RIKLOG(@"Before update - target: %@, action: %@, enabled: %d", [zoomButton target], NSStringFromSelector([zoomButton action]), [zoomButton isEnabled]);

      // Ensure target and action are maintained
      [zoomButton setTarget:self];
      [zoomButton setAction:@selector(RIKzoomButtonClicked:)];

      [zoomButton setFrame: zoomButtonRect];
      [zoomButton setEnabled: YES];  // Ensure button stays enabled
      [zoomButton setHidden: NO];    // Ensure button stays visible
      [zoomButton setNeedsDisplay: YES];  // Force redraw

      // Make sure the button is properly positioned in view hierarchy
      [zoomButton removeFromSuperview];
      [self addSubview: zoomButton];

      RIKLOG(@"After update - target: %@, action: %@, enabled: %d, hidden: %d", [zoomButton target], NSStringFromSelector([zoomButton action]), [zoomButton isEnabled], [zoomButton isHidden]);
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

- (void) RIKzoomButtonClicked:(id)sender
{
  RIKLOG(@"*** ZOOM BUTTON CLICKED! sender: %@, window: %@", sender, window);
  RIKLOG(@"*** Window isZoomed: %d", [window isZoomed]);

  if ([window isZoomed]) {
    // Window is zoomed, manually restore it to original frame
    RIKLOG(@"*** Window is zoomed, attempting manual unzoom");

    NSValue *originalFrameValue = objc_getAssociatedObject(window, &originalFrameKey);
    if (originalFrameValue) {
      NSRect originalFrame = [originalFrameValue rectValue];
      RIKLOG(@"*** Restoring window to original frame: %@", NSStringFromRect(originalFrame));
      [window setFrame:originalFrame display:YES animate:NO];

      // Clear the stored frame
      objc_setAssociatedObject(window, &originalFrameKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
      RIKLOG(@"*** No original frame stored, falling back to performZoom");
      [window performZoom:sender];
    }
  } else {
    // Window is not zoomed, store current frame and zoom it
    RIKLOG(@"*** Window is not zoomed, storing frame and zooming");

    // Store current frame before zooming
    NSRect currentFrame = [window frame];
    NSValue *frameValue = [NSValue valueWithRect:currentFrame];
    objc_setAssociatedObject(window, &originalFrameKey, frameValue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    RIKLOG(@"*** Stored original frame: %@", NSStringFromRect(currentFrame));

    [window zoom:sender];
  }

  RIKLOG(@"*** After zoom call - Window isZoomed: %d", [window isZoomed]);
}

@end
