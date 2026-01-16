#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Eau.h"
#import "AppearanceMetrics.h"

@interface GWDialog : NSWindow
@end

@interface GWDialogView : NSView
@end

@interface NSWindow (EauDialogServices)
- (id)eau_validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType;
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

// Apply AppearanceMetrics layout and Mac-like dialog behavior for GWDialog.
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

  /* Don't set key equivalents here - the buttons already have target/action set
     by the original init, and adding key equivalents can interfere with that. */

  // Set up key view loop for tab navigation.
  [editField setNextKeyView: okButt];
  [okButt setNextKeyView: cancelButt];
  [cancelButt setNextKeyView: editField];

  // Set initial first responder to the edit field for immediate keyboard input.
  [dialog setInitialFirstResponder: editField];

  // Position dialog using golden ratio centering.
  [dialog center];

  // Log dialog content for diagnostics.
  EAULOG(@"EauDialog: GWDialog layout title='%@' edit='%@' switch='%@'", 
         [titleField stringValue],
         [editField stringValue],
         (switchButt != nil) ? [switchButt title] : @"");
}

@implementation GWDialog (Eau)

+ (void)load
{
  Class dialogClass = NSClassFromString(@"GWDialog");
  if (dialogClass == nil)
    {
      return;
    }

  Method originalInit = class_getInstanceMethod(dialogClass,
                                                @selector(initWithTitle:editText:switchTitle:));
  Method eauInit = class_getInstanceMethod(dialogClass,
                                           @selector(eau_initWithTitle:editText:switchTitle:));
  if (originalInit && eauInit)
    {
      method_exchangeImplementations(originalInit, eauInit);
    }

  Method originalRunModal = class_getInstanceMethod(dialogClass, @selector(runModal));
  (void)originalRunModal;

  // Swizzle NSWindow validRequestorForSendType:returnType: to avoid crashes
  // when services menu validates while GWDialog is modal.
  Class windowClass = [NSWindow class];
  Method origValid = class_getInstanceMethod(windowClass, @selector(validRequestorForSendType:returnType:));
  Method eauValid = class_getInstanceMethod(windowClass, @selector(eau_validRequestorForSendType:returnType:));
  if (origValid && eauValid)
    {
      method_exchangeImplementations(origValid, eauValid);
    }

  /* keyDown swizzle removed - key equivalents are set directly on buttons
     via setKeyEquivalent: in EAULayoutGWDialog, which is the proper way
     to handle Enter and Escape keys. */
}

- (id)eau_initWithTitle: (NSString *)title
               editText: (NSString *)eText
            switchTitle: (NSString *)swTitle
{
  self = [self eau_initWithTitle: title editText: eText switchTitle: swTitle];
  if (self != nil)
    {
      EAULayoutGWDialog((GWDialog *)self);
    }
  return self;
}

@end

@implementation NSWindow (EauDialogServices)

- (id)eau_validRequestorForSendType:(NSString *)sendType returnType:(NSString *)returnType
{
  if ([self isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      return nil;
    }
  return [self eau_validRequestorForSendType: sendType returnType: returnType];
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
  [[NSColor windowBackgroundColor] setFill];
  NSRectFill(rect);
}

@end
