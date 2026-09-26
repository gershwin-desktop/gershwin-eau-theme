/* GBSheet.h - window-modal sheets shared between the sheet categories
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* libs-gui has no NSWindow -endSheet: family; GBSheetManager adds them at
 * runtime (only when missing, so a future upstream version wins). */
@interface NSWindow (GBSheetCocoaAPI)
- (void)endSheet:(NSWindow *)sheet;
- (void)endSheet:(NSWindow *)sheet returnCode:(NSModalResponse)returnCode;
- (void)beginCriticalSheet:(NSWindow *)sheet
         completionHandler:(GSNSWindowDidEndSheetCallbackBlock)handler;
- (NSArray *)sheets;
@end

/* User default; NO restores the libs-gui app-modal behaviour. */
#define GBWindowModalSheetsDefault @"GBWindowModalSheets"

BOOL GBSheetsEnabled(void);

/* Starts a window-modal session and returns at once.  Exactly one of
 * delegate/didEnd or handler is used for the end callback. */
void GBSheetBegin(NSWindow *sheet, NSWindow *parent, id delegate, SEL didEnd, void *contextInfo,
                  GSNSWindowDidEndSheetCallbackBlock handler, BOOL critical);

/* The next GBSheetBegin keeps owner alive until that sheet has reported its
 * end; set around a call that ends in -beginSheet: (see NSAlert+GBSheet.m). */
void GBSheetSetNextOwner(id owner);

/* Returns NO when sheet is not a window-modal sheet (active or queued). */
BOOL GBSheetEnd(NSWindow *sheet, NSInteger returnCode);

BOOL GBSheetIsManaged(NSWindow *sheet);
BOOL GBSheetIsActive(NSWindow *sheet);
NSWindow *GBSheetParentOf(NSWindow *sheet);
NSWindow *GBSheetActiveSheetOf(NSWindow *parent);
NSArray *GBSheetSheetsOf(NSWindow *parent);

/* The sheet a -stopModalWithCode: without a matching app-modal session was
 * meant for, or nil.  libs-gui panels end themselves that way. */
NSWindow *GBSheetTargetForStopModal(void);

/* YES when events for sheet must pass an app-modal session: the sheet is
 * attached (maybe indirectly) to that session's window. */
BOOL GBSheetWorksWhenModal(NSWindow *sheet);

/* Teaches the sheet's class (and the superclasses defining them) to answer
 * key/modal questions for an attached sheet; done lazily because sheets
 * are often private panel classes that do not exist at +load time. */
void GBSheetPrepareClass(Class cls);

/* -performClose: on a document window: YES when the unsaved-changes
 * question was put up as a sheet and the close continues from its answer. */
BOOL GBSheetDocumentWindowWillClose(NSWindow *window, id sender);

/* Re-placement after the parent moved or resized. */
void GBSheetPlace(NSWindow *sheet);

/* X11 window-manager hints (GBSheetX11.m); no-ops on other backends. */
void GBSheetX11Attach(NSWindow *sheet, NSWindow *parent);
void GBSheetX11Detach(NSWindow *sheet);

/* Chains like the rest of the bundle: the replacement selector must be
 * implemented in a category of cls and calls itself to reach the original. */
static inline BOOL GBSheetSwizzle(Class cls, SEL orig, SEL repl)
{
  Method o = class_getInstanceMethod(cls, orig);
  Method r = class_getInstanceMethod(cls, repl);

  if (o == NULL || r == NULL) {
    return NO;
  }
  if (class_addMethod(cls, orig, method_getImplementation(r), method_getTypeEncoding(r))) {
    class_replaceMethod(cls, repl, method_getImplementation(o), method_getTypeEncoding(o));
  }
  else {
    method_exchangeImplementations(o, r);
  }
  return YES;
}
