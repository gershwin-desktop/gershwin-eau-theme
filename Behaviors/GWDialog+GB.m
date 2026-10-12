/* GWDialog+GB.m - keyboard handling for Workspace's GWDialog
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Users expect to type into a dialog as soon as it appears, Return to press
 * OK, Escape to press Cancel and Tab to move between the controls.  GWDialog
 * (GWorkspace) does none of that by itself, so it is wired up here once the
 * dialog is built.  The theme restyles the dialog first through the optional
 * -gbLayoutGWDialog: hook.
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "GBTheme.h"
#import "GBThemeHooks+GWDialog.h"

@interface GWDialog : NSWindow
@end

@interface NSWindow (GBDialogServices)
- (id) gb_validRequestorForSendType: (NSString *)sendType returnType: (NSString *)returnType;
@end

@interface GWDialog (GBInit)
- (id) gb_initWithTitle: (NSString *)title
               editText: (NSString *)eText
            switchTitle: (NSString *)swTitle __attribute__((objc_method_family(init)));
- (NSModalResponse) gb_runModal;
@end

// GWDialog keeps its controls in private ivars; reach them by name.
static id GBGetIvarObject(id obj, const char *name)
{
  Ivar ivar = class_getInstanceVariable([obj class], name);
  if (ivar == NULL)
    {
      return nil;
    }
  return object_getIvar(obj, ivar);
}

static void GBSetUpGWDialogKeyboard(GWDialog *dialog)
{
  NSView *dialogView = (NSView *)GBGetIvarObject(dialog, "dialogView");
  NSTextField *titleField = (NSTextField *)GBGetIvarObject(dialog, "titleField");
  NSTextField *editField = (NSTextField *)GBGetIvarObject(dialog, "editField");
  NSButton *cancelButt = (NSButton *)GBGetIvarObject(dialog, "cancelButt");
  NSButton *okButt = (NSButton *)GBGetIvarObject(dialog, "okButt");

  /* A GWDialog missing any of these is not the one this was written for;
   * leave it alone rather than half-configure it. */
  if (dialogView == nil || titleField == nil || editField == nil
      || cancelButt == nil || okButt == nil)
    {
      return;
    }

  /* Only touch buttons that are fully wired, so the key equivalents never
   * point at a button that would do nothing. */
  if ([okButt target] && [okButt action])
    {
      [okButt setKeyEquivalent: @"\r"];
      [okButt setKeyEquivalentModifierMask: 0];

      NSButtonCell *okCell = [okButt cell];
      if (okCell)
        {
          [dialog setDefaultButtonCell: okCell];
        }
    }
  else
    {
      NSDebugLog(@"GWDialog+GB: OK button missing target or action, no Return key");
    }

  if ([cancelButt target] && [cancelButt action])
    {
      [cancelButt setKeyEquivalent: @"\e"];
      [cancelButt setKeyEquivalentModifierMask: 0];
    }
  else
    {
      NSDebugLog(@"GWDialog+GB: Cancel button missing target or action, no Escape key");
    }

  // Tab cycles editField -> OK -> Cancel -> editField.
  [editField setNextKeyView: okButt];
  [okButt setNextKeyView: cancelButt];
  [cancelButt setNextKeyView: editField];

  /* The edit field gets focus as soon as the dialog opens, so the user can
   * type without clicking first.  This relies on GWDialog having no delegate
   * (see NSWindow+GBDefaultButton.m). */
  [dialog setInitialFirstResponder: editField];
}

@implementation GWDialog (GB)

+ (void) load
{
  Class dialogClass = NSClassFromString(@"GWDialog");
  if (dialogClass == nil)
    {
      return;
    }

  Method originalInit = class_getInstanceMethod(dialogClass,
                                                @selector(initWithTitle:editText:switchTitle:));
  Method gbInit = class_getInstanceMethod(dialogClass,
                                          @selector(gb_initWithTitle:editText:switchTitle:));
  if (originalInit && gbInit)
    {
      method_exchangeImplementations(originalInit, gbInit);
    }

  Method originalRunModal = class_getInstanceMethod(dialogClass, @selector(runModal));
  Method gbRunModal = class_getInstanceMethod(dialogClass, @selector(gb_runModal));
  if (originalRunModal && gbRunModal)
    {
      method_exchangeImplementations(originalRunModal, gbRunModal);
    }

  /* The services menu validating against a modal GWDialog crashed; GWDialog
   * has nothing to offer services anyway. */
  Class windowClass = [NSWindow class];
  Method origValid = class_getInstanceMethod(windowClass,
                                             @selector(validRequestorForSendType:returnType:));
  Method gbValid = class_getInstanceMethod(windowClass,
                                           @selector(gb_validRequestorForSendType:returnType:));
  if (origValid && gbValid)
    {
      method_exchangeImplementations(origValid, gbValid);
    }
}

- (id) gb_initWithTitle: (NSString *)title
               editText: (NSString *)eText
            switchTitle: (NSString *)swTitle
{
  id dialog = [self gb_initWithTitle: title editText: eText switchTitle: swTitle];
  if (dialog != nil)
    {
      [GBThemeIfResponds(@selector(gbLayoutGWDialog:)) gbLayoutGWDialog: dialog];
      GBSetUpGWDialogKeyboard((GWDialog *)dialog);
    }
  return dialog;
}

/* GWDialog's own -runModal only calls -[NSApp runModalForWindow:], which
 * shows the dialog without making it key, so keyboard input went nowhere until
 * the user clicked it.  Activate the app and make the dialog key first. */
- (NSModalResponse) gb_runModal
{
  [[NSApplication sharedApplication] activateIgnoringOtherApps: YES];
  [self makeKeyAndOrderFront: nil];

  NSDebugLog(@"GWDialog+GB: key=%d first responder=%@", [self isKeyWindow],
             [[self firstResponder] class]);

  // Closing the dialog from outside must still end the modal session.
  id closeObs = [[NSNotificationCenter defaultCenter]
    addObserverForName: NSWindowWillCloseNotification
                object: self
                 queue: nil
            usingBlock: ^(NSNotification *note) {
              @try {
                [NSApp abortModal];
              } @catch (id ex) {}
            }];

  NSModalResponse result = [self gb_runModal];

  [[NSNotificationCenter defaultCenter] removeObserver: closeObs];
  return result;
}

@end

@implementation NSWindow (GBDialogServices)

- (id) gb_validRequestorForSendType: (NSString *)sendType returnType: (NSString *)returnType
{
  if ([self isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      return nil;
    }
  return [self gb_validRequestorForSendType: sendType returnType: returnType];
}

@end
