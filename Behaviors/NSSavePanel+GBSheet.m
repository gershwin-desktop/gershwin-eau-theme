/* NSSavePanel+GBSheet.m - save/open panels as window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - -[NSSavePanel beginSheetModalForWindow:
 * completionHandler:] should go through -[NSWindow beginSheet:
 * completionHandler:] instead of -runModalForWindow:relativeToWindow:.
 *
 * -beginSheetForDirectory:... already goes through NSApp's beginSheet and
 * needs nothing here; the panel's OK/Cancel end it via -stopModalWithCode:
 * (see NSApplication+GBSheet.m).
 */

#import <AppKit/AppKit.h>

#import "GBSheet.h"

@interface NSSavePanel (GBSheet)
- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                  completionHandler:(GSSavePanelCompletionHandler)handler;
@end

@implementation NSSavePanel (GBSheet)

+ (void)load
{
  GBSheetSwizzle([NSSavePanel class], @selector(beginSheetModalForWindow:completionHandler:),
                 @selector(gb_beginSheetModalForWindow:completionHandler:));
}

/* The original body is an app-modal runModalForWindow:, so it only runs
 * when sheets are off. */
- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                  completionHandler:(GSSavePanelCompletionHandler)handler
{
  if (GBSheetsEnabled() && window != nil && window != self) {
    GBSheetBegin(self, window, nil, NULL, NULL, handler, NO);
    return;
  }
  [self gb_beginSheetModalForWindow:window completionHandler:handler];
}

@end
