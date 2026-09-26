/* NSAlert+GB.m - how a modal NSAlert is run
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBThemeHooks+Alert.h"
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

/* Private libs-gui method; the theme may have swizzled it to build its own
 * panel, which is exactly what we want to call. */
@interface NSAlert (GBPrivate)
- (void)_setupPanel;
@end

static char GBAlertRetiredPanelKey;

@protocol GBAlertPanelResult
- (NSInteger)result;
@end

/* Behavior of -[NSAlert runModal] under any theme:
 * - never show an alert without text (an application bug, not a question)
 * - run on the main thread even when called from another one
 * - activate the app and make the alert key so it takes input without a click
 * - give the first editable text field (accessory views) the initial focus
 * - keep the panel alive past the modal session to avoid a teardown crash
 *
 * libs-gui's runModal is not chained to: it releases _window right after the
 * modal session ends, and that immediate release is the crash the deferred
 * gb_cleanupPanel exists to avoid. */
@implementation NSAlert (GB)

+ (void)load
{
  Class alertClass = [NSAlert class];
  SEL origSel = @selector(runModal);
  SEL newSel = @selector(gb_runModal);
  Method origMethod = class_getInstanceMethod(alertClass, origSel);
  Method newMethod = class_getInstanceMethod(alertClass, newSel);

  if (origMethod == NULL || newMethod == NULL) {
    NSDebugLog(@"GershwinBehaviors: could not find -[NSAlert runModal] to swizzle");
    return;
  }
  if (class_addMethod(alertClass, origSel, method_getImplementation(newMethod),
                      method_getTypeEncoding(newMethod))) {
    class_replaceMethod(alertClass, newSel, method_getImplementation(origMethod),
                        method_getTypeEncoding(origMethod));
  }
  else {
    method_exchangeImplementations(origMethod, newMethod);
  }
}

- (NSInteger)gb_runModal
{
  /* Full text and caller in the log so CI can tell which code path raised an
   * unexpected modal alert (the UI test suite fails on any). */
  NSLog(@"GershwinBehaviors: NSAlert runModal - messageText=\"%@\" informativeText=\"%@\"",
        [self messageText], [self informativeText]);
  NSLog(@"GershwinBehaviors: NSAlert caller stack: %@", [NSThread callStackSymbols]);
  @try {
    if (![NSThread isMainThread]) {
      __block NSInteger result;
      dispatch_sync(dispatch_get_main_queue(), ^{
        result = [self gb_runModal];
      });
      return result;
    }

    NSCharacterSet *blank = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *msgText = [[self messageText] stringByTrimmingCharactersInSet:blank];
    NSString *infoText = [[self informativeText] stringByTrimmingCharactersInSet:blank];
    if ([msgText length] == 0 && [infoText length] == 0) {
      NSLog(@"GershwinBehaviors: NSAlert suppressed - both messageText and informativeText "
            @"are empty/whitespace (probably a bug in the application)");
      return NSAlertErrorReturn;
    }

    /* A rerun within the cleanup delay would have libs-gui's _setupPanel
     * overwrite (leak) the previous panel and the pending cleanup detach the
     * new one mid-session; retire the previous panel now instead. */
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(gb_cleanupPanel)
                                               object:nil];
    [self gb_cleanupPanel];
    [self _setupPanel];

    /* Audible cue that an alert needs attention; -beep is provided by the
     * theme's sound support when present. */
    NSApplication *app = [NSApplication sharedApplication];
    if ([app respondsToSelector:@selector(beep)]) {
      [app performSelector:@selector(beep)];
    }

    NSWindow *window = nil;
    @try {
      window = [self valueForKey:@"_window"];
    }
    @catch (NSException *exception) {
      Ivar windowIvar = class_getInstanceVariable([self class], "_window");
      if (windowIvar) {
        window = object_getIvar(self, windowIvar);
      }
    }

    if (window == nil) {
      return NSAlertFirstButtonReturn;
    }

    NSInteger result = NSAlertErrorReturn;

    /* An alert with a text field is asking for input: the cursor must be in
     * it right away, not after a click. */
    for (NSView *view in [[window contentView] subviews]) {
      if ([view isKindOfClass:[NSTextField class]] && [(NSTextField *)view isEditable]) {
        [window setInitialFirstResponder:view];
        break;
      }
    }

    /* Without this the alert can come up behind the key window of another
     * app, or unfocused, so the keyboard does not reach it.
     * TODO: Upstream to GNUstep - -[NSAlert runModal] should activate the app
     * and make its panel key before entering the modal session.
     * Placed before it is first shown: see prepareAlertPanelForDisplay:. */
    id preparer = GBThemeIfResponds(@selector(prepareAlertPanelForDisplay:));
    if (preparer != nil) {
      [preparer prepareAlertPanelForDisplay:window];
    }
    else {
      [window center];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];

    id theme = GBThemeIfResponds(@selector(runModalForAlertPanel:result:));
    if (theme == nil || ![theme runModalForAlertPanel:window result:&result]) {
      [NSApp activateIgnoringOtherApps:YES];
      [window center];
      [window orderFrontRegardless];
      [window makeKeyAndOrderFront:nil];
      [NSApp runModalForWindow:window];
      if ([window respondsToSelector:@selector(result)]) {
        result = [(id<GBAlertPanelResult>)window result];
      }
    }

    [window orderOut:self];

    @try {
      [self setValue:@(result) forKey:@"_result"];
    }
    @catch (NSException *exception) {
    }

    /* Runs in the modal mode as well so nested alerts are cleaned up while an
     * outer modal session is still running. */
    [self performSelector:@selector(gb_cleanupPanel)
               withObject:nil
               afterDelay:0.1
                  inModes:[NSArray
                              arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
    return result;
  }
  @catch (NSException *exception) {
    NSLog(@"GershwinBehaviors: exception in NSAlert runModal: %@", exception);
    return NSAlertErrorReturn;
  }
}

/* Detaches the finished panel from the alert without releasing it yet.
 * Releasing the panel right after its modal session crashes (segfault) while
 * the X11 back end still has pending work for it.  _window owns a retain
 * (libs-gui's _setupPanel and a theme's replacement both hand it +1), which
 * moves to an associated object so the panel dies with the alert, by which
 * time it is inert: ordered out, no delegate and no default-button
 * animation.  Nilling the ivar without that would leak one panel per alert.
 * TODO: Upstream to GNUstep - window teardown in libs-gui/libs-back should
 * survive releasing a just-closed modal panel. */
- (void)gb_cleanupPanel
{
  Ivar windowIvar = class_getInstanceVariable([self class], "_window");
  if (windowIvar == NULL) {
    @try {
      [self setValue:nil forKey:@"_window"];
    }
    @catch (NSException *exception) {
    }
    return;
  }

  id window = object_getIvar(self, windowIvar);
  if (window == nil) {
    return;
  }
  @try {
    if ([window respondsToSelector:@selector(setDefaultButtonCell:)]) {
      [window setDefaultButtonCell:nil];
    }
    if ([window respondsToSelector:@selector(setDelegate:)]) {
      [window setDelegate:nil];
    }
  }
  @catch (NSException *e) {
  }
  objc_setAssociatedObject(self, &GBAlertRetiredPanelKey, window,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  object_setIvar(self, windowIvar, nil);
  /* Balances the retain the ivar held; ARC cannot see it (MRC ivar). */
  (void)(__bridge_transfer id)(__bridge void *)window;
}

@end
