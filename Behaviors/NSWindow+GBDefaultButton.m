/* NSWindow+GBDefaultButton.m - installing a window's default button cell
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "GBTheme.h"
#import "GBThemeHooks+DefaultButton.h"

/* Stands in as the window delegate while a default button is installed, only
 * to answer -windowWillReturnFieldEditor:toObject: with nil (the window's own
 * field editor).  Field editor requests through a delegate without a proper
 * implementation of that method crashed with an objc_msgSend_stret mix-up on
 * ARM64, so windows that have no delegate of their own get this one.
 *
 * TODO: Upstream to GNUstep - -[NSWindow fieldEditor:forObject:] must not
 * crash on ARM64 when consulting a delegate; then this placeholder can go. */
@interface GBFieldEditorDelegate : NSObject
@end

@implementation GBFieldEditorDelegate
- (id) windowWillReturnFieldEditor: (NSWindow *)sender toObject: (id)anObject
{
  return nil;
}
@end

static const void *kGBFieldEditorDelegateKey = &kGBFieldEditorDelegateKey;
static const void *kGBDefaultButtonInstallingKey = &kGBDefaultButtonInstallingKey;

/* NSWindow keeps its delegate as a plain unretained reference, so the
 * placeholder has to be unhooked from the window *before* the association
 * drops the last reference to it.  Releasing it first leaves -delegate handing
 * out a freed object, which ARC then tries to retain. */
static void GBReleaseFieldEditorDelegate(NSWindow *window)
{
  id placeholder = objc_getAssociatedObject(window, kGBFieldEditorDelegateKey);

  if (placeholder == nil)
    {
      return;
    }
  if ([window delegate] == placeholder)
    {
      [window setDelegate: nil];
    }
  objc_setAssociatedObject(window, kGBFieldEditorDelegateKey, nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void GBInstallFieldEditorDelegate(NSWindow *window)
{
  /* GWDialog sets its edit field as initial first responder; leaving it
   * without a delegate keeps that focus setup out of the way of any field
   * editor negotiation. */
  if ([window isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      return;
    }
  if ([window delegate] != nil)
    {
      return;
    }

  GBFieldEditorDelegate *placeholder = [[GBFieldEditorDelegate alloc] init];
  objc_setAssociatedObject(window, kGBFieldEditorDelegateKey, placeholder,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [window setDelegate: (id<NSWindowDelegate>)placeholder];
}

@interface NSWindow (GBDefaultButton)
- (void) gb_setDefaultButtonCell: (NSButtonCell *)aCell;
@end

@implementation NSWindow (GBDefaultButton)

+ (void) load
{
  Class cls = [NSWindow class];
  Method orig = class_getInstanceMethod(cls, @selector(setDefaultButtonCell:));
  Method swiz = class_getInstanceMethod(cls, @selector(gb_setDefaultButtonCell:));

  if (orig && swiz)
    {
      method_exchangeImplementations(orig, swiz);
    }
}

- (void) gb_setDefaultButtonCell: (NSButtonCell *)aCell
{
  /* The original sets the Return key equivalent on the cell, which travels
   * through GSTheme into the button and button cell categories and may hand
   * this very cell to this window again.  Letting that re-entry run would
   * make the theme set its default-button state up twice and tear the first
   * one down again as soon as the outer call resumed. */
  if (aCell != nil
      && objc_getAssociatedObject(self, kGBDefaultButtonInstallingKey) == aCell)
    {
      NSDebugLog(@"NSWindow+GB: ignoring re-entrant setDefaultButtonCell: for cell %p", aCell);
      return;
    }

  GBReleaseFieldEditorDelegate(self);

  if (aCell == nil)
    {
      [self gb_setDefaultButtonCell: nil];
      [GBThemeIfResponds(@selector(gbDefaultButtonCellChanged:forWindow:))
        gbDefaultButtonCellChanged: nil
                         forWindow: self];
      return;
    }

  objc_setAssociatedObject(self, kGBDefaultButtonInstallingKey, aCell,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  @try
    {
      [self gb_setDefaultButtonCell: aCell];
      GBInstallFieldEditorDelegate(self);
      [GBThemeIfResponds(@selector(gbDefaultButtonCellChanged:forWindow:))
        gbDefaultButtonCellChanged: aCell
                         forWindow: self];
    }
  @finally
    {
      objc_setAssociatedObject(self, kGBDefaultButtonInstallingKey, nil,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

@end
