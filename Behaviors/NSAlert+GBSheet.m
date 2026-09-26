/* NSAlert+GBSheet.m - keep an alert alive while its sheet is up
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - -[NSAlert beginSheetModalForWindow:...] should
 * keep the alert (and its panel) alive until the sheet ends instead of
 * releasing the panel as soon as -beginSheet: returns.
 *
 * libs-gui builds the panel, hands it to -beginSheet: and releases it right
 * after, which was fine while -beginSheet: blocked.  Now that sheets return
 * at once, callers routinely drop the NSAlert straight away (Cocoa keeps it
 * alive while its sheet is up), so the session takes ownership of it.
 */

#import <AppKit/AppKit.h>

#import "GBSheet.h"

@interface NSAlert (GBSheet)
- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                      modalDelegate:(id)delegate
                     didEndSelector:(SEL)didEndSelector
                        contextInfo:(void *)contextInfo;
- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                  completionHandler:(GSNSWindowDidEndSheetCallbackBlock)handler;
@end

@implementation NSAlert (GBSheet)

+ (void)load
{
  Class cls = [NSAlert class];

  GBSheetSwizzle(cls, @selector(beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:),
                 @selector(gb_beginSheetModalForWindow:modalDelegate:didEndSelector:contextInfo:));
  GBSheetSwizzle(cls, @selector(beginSheetModalForWindow:completionHandler:),
                 @selector(gb_beginSheetModalForWindow:completionHandler:));
}

- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                      modalDelegate:(id)delegate
                     didEndSelector:(SEL)didEndSelector
                        contextInfo:(void *)contextInfo
{
  GBSheetSetNextOwner(self);
  [self gb_beginSheetModalForWindow:window
                      modalDelegate:delegate
                     didEndSelector:didEndSelector
                        contextInfo:contextInfo];
  GBSheetSetNextOwner(nil);
}

- (void)gb_beginSheetModalForWindow:(NSWindow *)window
                  completionHandler:(GSNSWindowDidEndSheetCallbackBlock)handler
{
  GBSheetSetNextOwner(self);
  [self gb_beginSheetModalForWindow:window completionHandler:handler];
  GBSheetSetNextOwner(nil);
}

@end
