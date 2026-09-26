/* NSApplication+GBSheet.m - NSApp entry points of window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - -[NSApplication beginSheet:modalForWindow:...]
 * should start a window-modal session and return at once, and -endSheet:
 * should end that session instead of calling -stopModal.
 */

#import <AppKit/AppKit.h>

#import "GBSheet.h"

@interface NSApplication (GBSheet)
- (void)gb_beginSheet:(NSWindow *)sheet
       modalForWindow:(NSWindow *)docWindow
        modalDelegate:(id)modalDelegate
       didEndSelector:(SEL)didEndSelector
          contextInfo:(void *)contextInfo;
- (void)gb_endSheet:(NSWindow *)sheet;
- (void)gb_endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode;
- (void)gb_stopModalWithCode:(NSInteger)returnCode;
@end

@implementation NSApplication (GBSheet)

+ (void)load
{
  Class cls = [NSApplication class];

  GBSheetSwizzle(cls,
                 @selector(beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:),
                 @selector(gb_beginSheet:modalForWindow:modalDelegate:didEndSelector:contextInfo:));
  GBSheetSwizzle(cls, @selector(endSheet:), @selector(gb_endSheet:));
  GBSheetSwizzle(cls, @selector(endSheet:returnCode:), @selector(gb_endSheet:returnCode:));
  GBSheetSwizzle(cls, @selector(stopModalWithCode:), @selector(gb_stopModalWithCode:));
}

/* The original body is the app-modal runModalForWindow: loop; it only runs
 * when sheets are off or there is no window to attach to (a modeless
 * "sheet" such as -[NSOpenPanel beginForDirectory:...]). */
- (void)gb_beginSheet:(NSWindow *)sheet
       modalForWindow:(NSWindow *)docWindow
        modalDelegate:(id)modalDelegate
       didEndSelector:(SEL)didEndSelector
          contextInfo:(void *)contextInfo
{
  if (GBSheetsEnabled() && sheet != nil && docWindow != nil && sheet != docWindow) {
    GBSheetBegin(sheet, docWindow, modalDelegate, didEndSelector, contextInfo, nil, NO);
    return;
  }
  [self gb_beginSheet:sheet
       modalForWindow:docWindow
        modalDelegate:modalDelegate
       didEndSelector:didEndSelector
          contextInfo:contextInfo];
}

- (void)gb_endSheet:(NSWindow *)sheet
{
  if (GBSheetEnd(sheet, NSRunStoppedResponse) == NO) {
    [self gb_endSheet:sheet];
  }
}

- (void)gb_endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode
{
  if (GBSheetEnd(sheet, returnCode) == NO) {
    [self gb_endSheet:sheet returnCode:returnCode];
  }
}

/* libs-gui panels (alerts, save/open panels) end themselves with
 * -stopModalWithCode: because they assume they run app-modal.  When that
 * stop cannot be meant for a running app-modal session it ends the sheet. */
- (void)gb_stopModalWithCode:(NSInteger)returnCode
{
  NSWindow *sheet = nil;

  if (returnCode != NSRunContinuesResponse) {
    sheet = GBSheetTargetForStopModal();
  }
  if (sheet != nil) {
    GBSheetEnd(sheet, returnCode);
    return;
  }
  [self gb_stopModalWithCode:returnCode];
}

@end
