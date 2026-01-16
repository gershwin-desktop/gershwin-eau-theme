//
// AppearanceMetrics.h
//
// Global appearance metrics for the theme, following documented HIG values.
// These values MUST be used wherever possible, e.g., for alert panels, dialogs, and other window types.
// Design rules are described in the comments of this file, they MUST be followed when creating or updating UI elements.
// Do NOT hardcode any layout values in the code, use these constants or create additional ones here instead.
//

#ifndef APPEARANCE_METRICS_H
#define APPEARANCE_METRICS_H

#import <AppKit/AppKit.h>
#import <math.h>

// Window dimensions
static const float METRICS_WIN_MIN_WIDTH = 500.0;
static const float METRICS_WIN_MIN_HEIGHT = 100.0;

// Icon size for dialogs and alerts shall be 64x64px
static const float METRICS_ICON_SIDE = 64.0;
// Standard alert layout margins
static const float METRICS_ICON_LEFT = 24.0;
static const float METRICS_ICON_TOP = 16.0;

// Text from left window edge if icon is present
// 24px left margin + 64px icon + 16px gap = shall be 104px left edge for title and message
static const float METRICS_TEXT_LEFT = 104.0;

// Vertical spacing between multiple text elements shall be 8px
static const float METRICS_TITLE_MESSAGE_GAP = 8.0; 

// Vertical spacing between multiple buttons shall be 12px
static const float METRICS_BUTTON_VERT_INTERSPACE = 12.0;
// Horizontal spacing between multiple buttons shall be 12px
static const float METRICS_BUTTON_HORIZ_INTERSPACE = 12.0;

// Normal buttons shall always be 20px high (resize any buttons requested to be 19-24px high to be 20px)
// unless they contain an icon, in which case they may be higher if needed
static const float METRICS_BUTTON_HEIGHT = 20.0;

// Small buttons shall always be 17px high (resize any buttons requested to be 14-18px high to be 17px)
static const float METRICS_BUTTON_SMALL_HEIGHT = 17.0;

// Mini buttons shall always be 15px high (resize any buttons requested to be 12-16px high to be 15px)
static const float METRICS_BUTTON_MINI_HEIGHT = 15.0;

// Standard minimum button width shall be 68px
static const float METRICS_BUTTON_MIN_WIDTH = 68.0;

// Margin between content and window edge shall be 14px at the top and 20px at the sides and bottom
static const float METRICS_CONTENT_TOP_MARGIN = 14.0;
static const float METRICS_CONTENT_SIDE_MARGIN = 20.0;
static const float METRICS_CONTENT_BOTTOM_MARGIN = 20.0;

// Radio buttons and checkboxes shall be 18x18px
static const float METRICS_RADIO_BUTTON_SIZE = 18.0;
// Line spacing for the label text of radio buttons and checkboxes shall be 20px (baseline to baseline, not whitespace)
static const float METRICS_RADIO_BUTTON_LINE_SPACING = 20.0;

// Small radio buttons and checkboxes shall be 14x14px
static const float METRICS_RADIO_BUTTON_SMALL_SIZE = 14.0;
// Vertical spacing between stacked checkboxes/radio buttons
static const float METRICS_CHECKBOX_STACK_SPACING = 5.0;
// Line spacing for the label text of small radio buttons and checkboxes shall be 18px (baseline to baseline, not whitespace)
static const float METRICS_RADIO_BUTTON_SMALL_LINE_SPACING = 18.0;

// Screen size scaling factor
static const float METRICS_SIZE_SCALE = 0.6;

// Text input fields shall be 22px high
static const float METRICS_TEXT_INPUT_FIELD_HEIGHT = 22.0;
// Small text input fields shall be 19px high
static const float METRICS_TEXT_INPUT_FIELD_SMALL_HEIGHT = 19.0;
// Mini text input fields shall be 15px high
static const float METRICS_TEXT_INPUT_FIELD_MINI_HEIGHT = 15.0;

// Vertical spacing between stacked text input fields
static const float METRICS_TEXT_FIELD_VERTICAL_SPACING = 10.0;
static const float METRICS_TEXT_FIELD_VERTICAL_SPACING_SMALL = 8.0;
static const float METRICS_TEXT_FIELD_VERTICAL_SPACING_MINI = 8.0;
// When the user selects text in a text input field, the selection rectangle is also 16px high
static const float METRICS_TEXT_INPUT_SELECTION_HEIGHT = 16.0;
// When a text input field has keyboard focus, a dark, translucent rectangle
// (which shall be 2px  wide at the top and 3px wide on the other three sides)
// appears around the outside edge of the field
static const float METRICS_TEXT_INPUT_FOCUS_RING_WIDTH_TOP = 2.0;
static const float METRICS_TEXT_INPUT_FOCUS_RING_WIDTH_SIDES = 3.0;

// Tabs shall be 20px high
static const float METRICS_TAB_HEIGHT = 20.0;

// Small tabs shall be 17px high
static const float METRICS_TAB_SMALL_HEIGHT = 17.0;

// Mini tabs shall be 15px high
static const float METRICS_TAB_MINI_HEIGHT = 15.0;

// Scroll bar width shall be 11px
static const float METRICS_SCROLLBAR_WIDTH = 11.0;

// Menus and menu items shall be 22px high
static const float METRICS_MENU_ITEM_HEIGHT = 22.0;

// Pop-up and combo box heights (full/small/mini)
static const float METRICS_POPUP_HEIGHT = 20.0;
static const float METRICS_POPUP_SMALL_HEIGHT = 17.0;
static const float METRICS_POPUP_MINI_HEIGHT = 15.0;

// Segmented control heights (full/small/mini) and textured full-size height
static const float METRICS_SEGMENTED_HEIGHT = 20.0;
static const float METRICS_SEGMENTED_SMALL_HEIGHT = 17.0;
static const float METRICS_SEGMENTED_MINI_HEIGHT = 15.0;
static const float METRICS_SEGMENTED_TEXTURED_HEIGHT = 25.0;

// Stepper dimensions (full/small/mini)
static const float METRICS_STEPPER_WIDTH = 13.0;
static const float METRICS_STEPPER_SMALL_WIDTH = 11.0;
static const float METRICS_STEPPER_MINI_WIDTH = 11.0;
static const float METRICS_STEPPER_HEIGHT = 22.0;
static const float METRICS_STEPPER_SMALL_HEIGHT = 19.0;
static const float METRICS_STEPPER_MINI_HEIGHT = 15.0;

// Slider dimensions (full/small/mini)
static const float METRICS_SLIDER_HEIGHT = 19.0;
static const float METRICS_SLIDER_HEIGHT_TICKS = 25.0;
static const float METRICS_SLIDER_SMALL_HEIGHT = 14.0;
static const float METRICS_SLIDER_SMALL_HEIGHT_TICKS = 19.0;
static const float METRICS_SLIDER_MINI_HEIGHT = 11.0;
static const float METRICS_SLIDER_MINI_HEIGHT_TICKS = 17.0;
static const float METRICS_SLIDER_VERTICAL_WIDTH = 18.0;
static const float METRICS_SLIDER_VERTICAL_WIDTH_TICKS = 24.0;
static const float METRICS_SLIDER_VERTICAL_SMALL_WIDTH = 14.0;
static const float METRICS_SLIDER_VERTICAL_SMALL_WIDTH_TICKS = 19.0;
static const float METRICS_SLIDER_VERTICAL_MINI_WIDTH = 11.0;
static const float METRICS_SLIDER_VERTICAL_MINI_WIDTH_TICKS = 17.0;

// Control Positioning in Dialogs
// All spacing between dialog elements shall be a multiple of 4px (4, 8, 12, 16, 20, or 24).
// Guidelines:
// - No space between window edge and scroll bars or frame for single-view document windows.
// - For mixed control dialogs, maintain:
//   - 8px between full-size controls (10px for small, 8px for mini)
//   - 20px from the left, right, and bottom window edges to controls
//   - 14px from the title bar to the topmost controls (12px from tab top to title bar)
// - Aim for a center-biased layout rather than a left-biased approach.
// - Use spacing to group controls rather than group boxes to reduce visual clutter.
// - No control or label shall be within 16px of a group box's borders.
// Control Spacing Guidelines
// - Group controls shall have 20px of vertical spacing; subgroups within groups shall have 16px.
// - Vertical spacing is determined by the tallest control in the row.
// - Checkboxes and radio buttons are spaced 5px between controls when stacked; labels are 8px from controls.
// - Text for controls (pop-up buttons, checkbox/radio groups) shall be 8px from the associated control.
// - Bevel button spacing varies: toolbar buttons shall be spaced 8px apart; avoid overlapping smaller buttons in palettes.
// - The OK/default button goes in the lower-right corner; a Cancel button shall be to its left, followed by any alternate buttons.
// - Preferred button order: alternate, Cancel, default, with a minimum of 12px spacing between full-size push buttons.
// 
// Spacing:
// - 8px: Between a control and its text label or icon.
static const float METRICS_SPACE_8 = 8.0;
// - 12px: Horizontally between push/pop-up buttons, text input fields, labels for control groups, subgroups, and tab control and window top.
static const float METRICS_SPACE_12 = 12.0;
// - 16px: Between group box edges and enclosed controls, between primary control groups, and top edge of window and topmost controls.
static const float METRICS_SPACE_16 = 16.0;
// - 20px: Between window bottom edge and enclosed controls, among control groups without group boxes, and between radio button/checkbox label baselines.
static const float METRICS_SPACE_20 = 20.0;
// - 24px: Between window edges and enclosed controls, and between inset tab panes and window edges.
static const float METRICS_SPACE_24 = 24.0;
//
// Fonts:
// - System Font: Regular, 13 pt
//   - Used for message text in dialogs, default font for lists and tables.
#define METRICS_FONT_SYSTEM_REGULAR_13 ([NSFont systemFontOfSize: 13])
// 
// - System Font (Emphasized): Bold, 13 pt
//   - Use sparingly, such as for titling groups of settings without a group box.
#define METRICS_FONT_SYSTEM_BOLD_13 ([NSFont boldSystemFontOfSize: 13])
// 
// - Small System Font: Regular, 11 pt
//   - Used for informative text, headers in lists, and Help Tags; provides additional info in settings windows.
#define METRICS_FONT_SYSTEM_REGULAR_11 ([NSFont systemFontOfSize: 11])
// 
// - Small System Font (Emphasized): Bold, 11 pt
//   - Same usage as Small System Font, but with emphasis.
#define METRICS_FONT_SYSTEM_BOLD_11 ([NSFont boldSystemFontOfSize: 11])
// 
// - Application Font: Regular, 13 pt
//   - Used throughout applications as the main font.
#define METRICS_FONT_APPLICATION_13 ([NSFont systemFontOfSize: 13])
// 
// - Label Font: Regular, 10 pt
//   - Used for labels with controls (e.g., sliders, icon bevel buttons); shall be used rarely in dialogs.
#define METRICS_FONT_LABEL_10 ([NSFont systemFontOfSize: 10])

// - Mini System Font: Regular, 9 pt
//   - Used for mini controls (rare).
#define METRICS_FONT_SYSTEM_REGULAR_9 ([NSFont systemFontOfSize: 9])

// Helper: pick HIG height by control size
static inline CGFloat EauHeightForControlSize(NSControlSize size,
																							CGFloat full,
																							CGFloat small,
																							CGFloat mini)
{
	switch (size)
		{
			case NSSmallControlSize: return small;
			case NSMiniControlSize: return mini;
			default: return full;
		}
}

// Helper: snap heights into a HIG target when within a min/max range
static inline CGFloat EauSnapControlHeight(CGFloat height,
																					 CGFloat minValue,
																					 CGFloat maxValue,
																					 CGFloat target)
{
	if (height >= minValue && height <= maxValue)
		return target;
	return height;
}

// Must not use horizontal lines in dialogs or alert panels, use spacing only

#endif // APPEARANCE_METRICS_H
