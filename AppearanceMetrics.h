//
// AppearanceMetrics.h
//
// Global appearance metrics for the theme, following documented HIG values.
// These values MUST be used wherever possible, e.g., for alert panels, dialogs, and other window types.
// Design intent is described in the comments.
//

#ifndef APPEARANCE_METRICS_H
#define APPEARANCE_METRICS_H

#import <AppKit/AppKit.h>

// Window dimensions
static const float METRICS_WIN_MIN_WIDTH = 500.0;
static const float METRICS_WIN_MIN_HEIGHT = 100.0;

// Icon size for dialogs and alerts shall be 64x64 pixels
static const float METRICS_ICON_SIDE = 64.0;
static const float METRICS_ICON_LEFT = 24.0;
static const float METRICS_ICON_TOP = 24.0;

// Text from left window edge if icon is present
// 24px left margin + 64px icon + 16px gap = shall be 104px left edge for title and message
static const float METRICS_TEXT_LEFT = 104.0;

// Vertical spacing between multiple text elements shall be 8px
static const float METRICS_TITLE_MESSAGE_GAP = 8.0; 

// Spacing between multiple buttons shall be 20px
static const float METRICS_BUTTON_INTERSPACE = 20.0;

// Normal buttons shall always be 24px high (resize any buttons requested to be 20-28px high to be 24px)
static const float METRICS_BUTTON_HEIGHT = 24.0;

// Small buttons shall always be 18px high (resize any buttons requested to be 16-20px high to be 18px)
static const float METRICS_BUTTON_SMALL_HEIGHT = 18.0; // TODO: Verify

static const float METRICS_BUTTON_MIN_WIDTH = 72.0;

// Margin between content and window edge shall be 15px at the top, 24px at the sides, and 20px at the bottom
static const float METRICS_CONTENT_TOP_MARGIN = 15.0;
static const float METRICS_CONTENT_SIDE_MARGIN = 24.0;
static const float METRICS_CONTENT_BOTTOM_MARGIN = 20.0;

// Screen size scaling factor
static const float METRICS_SIZE_SCALE = 0.6;

// Large system font size shall be 16px (NOT point!) bold
#define METRICS_TITLE_FONT [NSFont boldSystemFontOfSize: 16] // TODO: Verify

// Small system font size shall be 13px (NOT point!)
#define METRICS_MESSAGE_FONT [NSFont systemFontOfSize: 13] // TODO: Verify

#endif // APPEARANCE_METRICS_H
