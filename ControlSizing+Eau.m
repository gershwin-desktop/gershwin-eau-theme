#import "Eau.h"
#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>
#import <objc/message.h>

@interface NSButtonCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSTextFieldCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSSearchFieldCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSSecureTextFieldCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSFormCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSTokenFieldCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSPopUpButtonCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSComboBoxCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSSegmentedCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSSliderCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSStepperCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSDatePickerCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSPathCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

@interface NSLevelIndicatorCell (EauThemeSizing)
- (NSSize) EAUcellSize;
@end

static NSControlSize EauControlSizeForCell(NSCell *cell)
{
  if ([cell respondsToSelector:@selector(controlSize)])
    return (NSControlSize)[(id)cell controlSize];
  return NSRegularControlSize;
}

static CGFloat EauSnapTextFieldHeight(CGFloat height)
{
  height = EauSnapControlHeight(height, 21.0, 23.0, METRICS_TEXT_INPUT_FIELD_HEIGHT);
  height = EauSnapControlHeight(height, 18.0, 20.0, METRICS_TEXT_INPUT_FIELD_SMALL_HEIGHT);
  height = EauSnapControlHeight(height, 14.0, 16.0, METRICS_TEXT_INPUT_FIELD_MINI_HEIGHT);
  return height;
}

static CGFloat EauSnapButtonHeight(CGFloat height)
{
  height = EauSnapControlHeight(height, 19.0, 24.0, METRICS_BUTTON_HEIGHT);
  height = EauSnapControlHeight(height, 14.0, 18.0, METRICS_BUTTON_SMALL_HEIGHT);
  height = EauSnapControlHeight(height, 12.0, 16.0, METRICS_BUTTON_MINI_HEIGHT);
  return height;
}

static CGFloat EauSnapPopupHeight(CGFloat height)
{
  height = EauSnapControlHeight(height, 18.0, 22.0, METRICS_POPUP_HEIGHT);
  height = EauSnapControlHeight(height, 16.0, 18.0, METRICS_POPUP_SMALL_HEIGHT);
  height = EauSnapControlHeight(height, 14.0, 16.0, METRICS_POPUP_MINI_HEIGHT);
  return height;
}

@implementation Eau(NSButtonCellSizing)
- (NSSize) _overrideNSButtonCellMethod_cellSize
{
  NSButtonCell *xself = (NSButtonCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSButtonCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  NSButtonType type = NSMomentaryPushInButton;
  if ([self respondsToSelector:@selector(buttonType)])
    {
      type = (NSButtonType)(NSInteger)objc_msgSend(self, @selector(buttonType));
    }
  NSControlSize controlSize = EauControlSizeForCell(self);

  if (type == NSSwitchButton || type == NSRadioButton)
    {
      CGFloat target = (controlSize == NSSmallControlSize || controlSize == NSMiniControlSize)
        ? METRICS_RADIO_BUTTON_SMALL_SIZE
        : METRICS_RADIO_BUTTON_SIZE;
      size.height = EauSnapControlHeight(size.height, target - 2.0, target + 2.0, target);
      return size;
    }

  size.height = EauSnapButtonHeight(size.height);

  if (type == NSMomentaryPushInButton || type == NSPushOnPushOffButton ||
      type == NSMomentaryLightButton || type == NSMomentaryChangeButton ||
      type == NSToggleButton)
    {
      if (size.width < METRICS_BUTTON_MIN_WIDTH)
        size.width = METRICS_BUTTON_MIN_WIDTH;
    }

  return size;
}

@end

@implementation Eau(NSTextFieldCellSizing)
- (NSSize) _overrideNSTextFieldCellMethod_cellSize
{
  NSTextFieldCell *xself = (NSTextFieldCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSTextFieldCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSSearchFieldCellSizing)
- (NSSize) _overrideNSSearchFieldCellMethod_cellSize
{
  NSSearchFieldCell *xself = (NSSearchFieldCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSSearchFieldCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSSecureTextFieldCellSizing)
- (NSSize) _overrideNSSecureTextFieldCellMethod_cellSize
{
  NSSecureTextFieldCell *xself = (NSSecureTextFieldCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSSecureTextFieldCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSPopUpButtonCellSizing)
- (NSSize) _overrideNSPopUpButtonCellMethod_cellSize
{
  NSPopUpButtonCell *xself = (NSPopUpButtonCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSPopUpButtonCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapPopupHeight(size.height);
  return size;
}

@end

@implementation Eau(NSComboBoxCellSizing)
- (NSSize) _overrideNSComboBoxCellMethod_cellSize
{
  NSComboBoxCell *xself = (NSComboBoxCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSComboBoxCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapPopupHeight(size.height);
  return size;
}

@end

@implementation Eau(NSSegmentedCellSizing)
- (NSSize) _overrideNSSegmentedCellMethod_cellSize
{
  NSSegmentedCell *xself = (NSSegmentedCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSSegmentedCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  NSControlSize controlSize = EauControlSizeForCell(self);
  NSSegmentStyle style = [self segmentStyle];
  CGFloat fullHeight = (style == NSSegmentStyleTexturedRounded ||
                        style == NSSegmentStyleTexturedSquare)
    ? METRICS_SEGMENTED_TEXTURED_HEIGHT
    : METRICS_SEGMENTED_HEIGHT;

  CGFloat targetHeight = EauHeightForControlSize(controlSize,
                                                 fullHeight,
                                                 METRICS_SEGMENTED_SMALL_HEIGHT,
                                                 METRICS_SEGMENTED_MINI_HEIGHT);

  size.height = EauSnapControlHeight(size.height, targetHeight - 2.0, targetHeight + 2.0, targetHeight);
  return size;
}

@end

@implementation Eau(NSSliderCellSizing)
- (NSSize) _overrideNSSliderCellMethod_cellSize
{
  NSSliderCell *xself = (NSSliderCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSSliderCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  NSControlSize controlSize = EauControlSizeForCell(self);
  BOOL hasTicks = [self numberOfTickMarks] > 0;
  BOOL isVertical = [self isVertical];

  CGFloat fullHeight = hasTicks ? METRICS_SLIDER_HEIGHT_TICKS : METRICS_SLIDER_HEIGHT;
  CGFloat smallHeight = hasTicks ? METRICS_SLIDER_SMALL_HEIGHT_TICKS : METRICS_SLIDER_SMALL_HEIGHT;
  CGFloat miniHeight = hasTicks ? METRICS_SLIDER_MINI_HEIGHT_TICKS : METRICS_SLIDER_MINI_HEIGHT;

  CGFloat fullWidth = hasTicks ? METRICS_SLIDER_VERTICAL_WIDTH_TICKS : METRICS_SLIDER_VERTICAL_WIDTH;
  CGFloat smallWidth = hasTicks ? METRICS_SLIDER_VERTICAL_SMALL_WIDTH_TICKS : METRICS_SLIDER_VERTICAL_SMALL_WIDTH;
  CGFloat miniWidth = hasTicks ? METRICS_SLIDER_VERTICAL_MINI_WIDTH_TICKS : METRICS_SLIDER_VERTICAL_MINI_WIDTH;

  if (isVertical)
    {
      CGFloat targetWidth = EauHeightForControlSize(controlSize, fullWidth, smallWidth, miniWidth);
      size.width = EauSnapControlHeight(size.width, targetWidth - 3.0, targetWidth + 3.0, targetWidth);
    }
  else
    {
      CGFloat targetHeight = EauHeightForControlSize(controlSize, fullHeight, smallHeight, miniHeight);
      size.height = EauSnapControlHeight(size.height, targetHeight - 3.0, targetHeight + 3.0, targetHeight);
    }

  return size;
}

@end

@implementation Eau(NSStepperCellSizing)
- (NSSize) _overrideNSStepperCellMethod_cellSize
{
  NSStepperCell *xself = (NSStepperCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSStepperCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  NSControlSize controlSize = EauControlSizeForCell(self);

  CGFloat targetHeight = EauHeightForControlSize(controlSize,
                                                 METRICS_STEPPER_HEIGHT,
                                                 METRICS_STEPPER_SMALL_HEIGHT,
                                                 METRICS_STEPPER_MINI_HEIGHT);
  CGFloat targetWidth = EauHeightForControlSize(controlSize,
                                                METRICS_STEPPER_WIDTH,
                                                METRICS_STEPPER_SMALL_WIDTH,
                                                METRICS_STEPPER_MINI_WIDTH);

  size.height = EauSnapControlHeight(size.height, targetHeight - 2.0, targetHeight + 2.0, targetHeight);
  size.width = EauSnapControlHeight(size.width, targetWidth - 2.0, targetWidth + 2.0, targetWidth);

  return size;
}

@end

@implementation Eau(NSFormCellSizing)
- (NSSize) _overrideNSFormCellMethod_cellSize
{
  NSFormCell *xself = (NSFormCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSFormCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSTokenFieldCellSizing)
- (NSSize) _overrideNSTokenFieldCellMethod_cellSize
{
  NSTokenFieldCell *xself = (NSTokenFieldCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSTokenFieldCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSDatePickerCellSizing)
- (NSSize) _overrideNSDatePickerCellMethod_cellSize
{
  NSDatePickerCell *xself = (NSDatePickerCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSDatePickerCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSPathCellSizing)
- (NSSize) _overrideNSPathCellMethod_cellSize
{
  NSPathCell *xself = (NSPathCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSPathCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  size.height = EauSnapTextFieldHeight(size.height);
  return size;
}

@end

@implementation Eau(NSLevelIndicatorCellSizing)
- (NSSize) _overrideNSLevelIndicatorCellMethod_cellSize
{
  NSLevelIndicatorCell *xself = (NSLevelIndicatorCell *)self;
  return [xself EAUcellSize];
}
@end

@implementation NSLevelIndicatorCell (EauThemeSizing)

- (NSSize) EAUcellSize
{
  NSSize size = [super cellSize];
  NSControlSize controlSize = EauControlSizeForCell(self);
  CGFloat targetHeight = EauHeightForControlSize(controlSize,
                                                 METRICS_TEXT_INPUT_FIELD_HEIGHT,
                                                 METRICS_TEXT_INPUT_FIELD_SMALL_HEIGHT,
                                                 METRICS_TEXT_INPUT_FIELD_MINI_HEIGHT);
  size.height = EauSnapControlHeight(size.height, targetHeight - 2.0, targetHeight + 2.0, targetHeight);
  return size;
}

@end
