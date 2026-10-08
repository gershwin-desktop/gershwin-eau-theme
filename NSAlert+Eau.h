//
// NSAlert+Eau.h
//
// Eau alert panel: layout, icon, text, sizing and the panel's own key
// handling.  Running an NSAlert modally lives in GershwinBehaviors.bundle.
//

#import <AppKit/AppKit.h>

@class EauAlertPanel;

// Category on NSAlert to hook into the alert system
@interface NSAlert (Eau)
@end

// Custom alert panel class for Eau theme
@interface EauAlertPanel : NSPanel
{
  NSButton      *defButton;
  NSButton      *altButton;
  NSButton      *othButton;
  NSButton      *icoButton;
  NSTextField   *titleField;
  NSTextField   *messageField;
  NSScrollView  *scroll;
  NSInteger     result;
  BOOL          isGreen;
}

- (id) initWithContentRect: (NSRect)rect;
- (NSInteger) runModal;
- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message;
- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
                 def: (NSString *)defaultButton
                 alt: (NSString *)alternateButton
               other: (NSString *)otherButton;
- (void) setButtons: (NSArray *)buttons;
- (void) sizePanelToFit;
- (void) buttonAction: (id)sender;
- (NSInteger) result;
- (NSButton *) defaultButton;
- (BOOL) isActivePanel;

// Internal method for GSAlertPanel swizzling (dynamically called)
- (id) eau_initWithoutGModelHelper;

@end
