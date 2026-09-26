#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "AppearanceMetrics.h"
#import "Behaviors/GBThemeHooks+GWDialog.h"

@interface GWDialog : NSWindow
@end

@interface GWDialogView : NSView
@end


// Helper to access ivars from GWDialog/GWDialogView safely via runtime.
static id EAUGetIvarObject(id obj, const char *name)
{
  Ivar ivar = class_getInstanceVariable([obj class], name);
  if (ivar == NULL)
    {
      return nil;
    }
  return object_getIvar(obj, ivar);
}

// Apply AppearanceMetrics layout to GWDialog.  Its keyboard handling lives in
// GershwinBehaviors (GWDialog+GB.m).
static void EAULayoutGWDialog(GWDialog *dialog)
{
  NSView *dialogView = (NSView *)EAUGetIvarObject(dialog, "dialogView");
  NSTextField *titleField = (NSTextField *)EAUGetIvarObject(dialog, "titleField");
  NSTextField *editField = (NSTextField *)EAUGetIvarObject(dialog, "editField");
  NSButton *switchButt = (NSButton *)EAUGetIvarObject(dialog, "switchButt");
  NSButton *cancelButt = (NSButton *)EAUGetIvarObject(dialog, "cancelButt");
  NSButton *okButt = (NSButton *)EAUGetIvarObject(dialog, "okButt");

  if (dialogView == nil || titleField == nil || editField == nil
      || cancelButt == nil || okButt == nil)
    {
      return;
    }

  BOOL useSwitch = (switchButt != nil);

  [titleField setFont: METRICS_FONT_SYSTEM_BOLD_13];
  [titleField setEditable: NO];
  [titleField setSelectable: NO];
  [titleField setBezeled: NO];
  [titleField setDrawsBackground: NO];
  [titleField setAlignment: NSLeftTextAlignment];

  [editField setFont: METRICS_FONT_SYSTEM_REGULAR_13];

  if (switchButt != nil)
    {
      [switchButt setFont: METRICS_FONT_SYSTEM_REGULAR_13];
    }

  [cancelButt setFont: METRICS_FONT_SYSTEM_REGULAR_13];
  [okButt setFont: METRICS_FONT_SYSTEM_BOLD_13];

  [cancelButt sizeToFit];
  [okButt sizeToFit];

  NSSize cancelSize = [cancelButt frame].size;
  NSSize okSize = [okButt frame].size;

  cancelSize.width = MAX(METRICS_BUTTON_MIN_WIDTH, cancelSize.width);
  okSize.width = MAX(METRICS_BUTTON_MIN_WIDTH, okSize.width);
  cancelSize.height = METRICS_BUTTON_HEIGHT;
  okSize.height = METRICS_BUTTON_HEIGHT;

  CGFloat minButtonRowWidth = cancelSize.width + okSize.width + METRICS_BUTTON_HORIZ_INTERSPACE;
  CGFloat contentWidth = MAX([dialogView frame].size.width,
                             METRICS_CONTENT_SIDE_MARGIN * 2 + minButtonRowWidth);

  NSSize titleSize = [[titleField cell] cellSize];
  CGFloat titleHeight = MAX(titleSize.height, 18.0);
  CGFloat switchHeight = METRICS_RADIO_BUTTON_SIZE;

  CGFloat y = METRICS_CONTENT_BOTTOM_MARGIN;
  CGFloat buttonY = y;
  y += METRICS_BUTTON_HEIGHT;

  CGFloat switchY = 0.0;
  if (useSwitch)
    {
      y += METRICS_SPACE_16;
      switchY = y;
      y += switchHeight;
    }

  y += METRICS_SPACE_16;
  CGFloat editY = y;
  y += METRICS_TEXT_INPUT_FIELD_HEIGHT;

  y += METRICS_SPACE_12;
  CGFloat titleY = y;
  y += titleHeight;

  y += METRICS_CONTENT_TOP_MARGIN;
  CGFloat contentHeight = y;

  [dialogView setFrame: NSMakeRect(0.0, 0.0, contentWidth, contentHeight)];
  [dialog setContentSize: NSMakeSize(contentWidth, contentHeight)];

  CGFloat x = METRICS_CONTENT_SIDE_MARGIN;
  CGFloat width = contentWidth - (METRICS_CONTENT_SIDE_MARGIN * 2);

  [titleField setFrame: NSMakeRect(x, titleY, width, titleHeight)];
  [editField setFrame: NSMakeRect(x, editY, width, METRICS_TEXT_INPUT_FIELD_HEIGHT)];

  if (useSwitch)
    {
      [switchButt setFrame: NSMakeRect(x, switchY, width, switchHeight)];
    }

  CGFloat okX = contentWidth - METRICS_CONTENT_SIDE_MARGIN - okSize.width;
  CGFloat cancelX = okX - METRICS_BUTTON_HORIZ_INTERSPACE - cancelSize.width;

  [cancelButt setFrame: NSMakeRect(cancelX, buttonY, cancelSize.width, cancelSize.height)];
  [okButt setFrame: NSMakeRect(okX, buttonY, okSize.width, okSize.height)];

  // Position dialog using golden ratio centering.
  [dialog center];

  // Log dialog content for diagnostics.
  NSDebugLog(@"EauDialog: GWDialog layout title='%@' edit='%@' switch='%@'", 
         [titleField stringValue],
         [(id)editField string],
         (switchButt != nil) ? [switchButt title] : @"");
}

@implementation Eau (GWDialog)

/* GershwinBehaviors calls this from GWDialog's initializer, before it sets up
 * Return, Escape and the Tab loop, so the dialog is laid out to Eau metrics
 * by the time the keyboard wiring runs. */
- (void) gbLayoutGWDialog: (NSWindow *)dialog
{
  if ([dialog isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      EAULayoutGWDialog((GWDialog *)dialog);
    }
}

@end

@implementation GWDialogView (Eau)

+ (void)load
{
  Class viewClass = NSClassFromString(@"GWDialogView");
  if (viewClass == nil)
    {
      return;
    }

  Method originalDraw = class_getInstanceMethod(viewClass, @selector(drawRect:));
  Method eauDraw = class_getInstanceMethod(viewClass, @selector(eau_drawRect:));
  if (originalDraw && eauDraw)
    {
      method_exchangeImplementations(originalDraw, eauDraw);
    }
}

- (void)eau_drawRect:(NSRect)rect
{
  if (!EauThemeIsActive())
    {
      [self eau_drawRect: rect];
      return;
    }
  [[NSColor windowBackgroundColor] setFill];
  NSRectFill(rect);
}

@end
