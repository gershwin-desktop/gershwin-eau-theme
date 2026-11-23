/* GBAutoSheet.m - synchronous dialogs shown as sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - NSRunAlertPanel, -[NSAlert runModal] and
 * -[NSSavePanel runModal] should not decide on their own that a question
 * about one document is app-modal and centered; libs-gui should offer the
 * questions a document asks while it closes (-[NSDocument canCloseDocument],
 * -windowShouldClose:) as sheets on that document's window, and
 * -runModalForWindow:relativeToWindow: should attach instead of centering.
 *
 * Most GNUstep applications ask "save changes?" and similar questions with a
 * blocking call (NSRunAlertPanel from -windowShouldClose:, -[NSAlert
 * runModal], -[NSSavePanel runModal]) and continue with the answer on the
 * next line, so they cannot be moved to the asynchronous sheet API without
 * source changes.  Here such a dialog is attached to its window as a sheet
 * for as long as its modal session runs (GBSheetManager does the placement,
 * the borderless style, the window-manager hints, the slide and the parent
 * state), and taken off again when the session ends, so the call still
 * blocks and returns the same code.
 *
 * The session stays app-modal while the sheet is up: a window-modal loop
 * nested in the caller's stack would run the application's event handling
 * (other windows, menus, timers) underneath a call that expects nothing to
 * change until it returns.  Only the look is a sheet.
 *
 * Which dialogs: alert panels (GSAlertPanel, NSAlert's panel, or whatever
 * panel the theme says is an alert), save panels (not open panels, which
 * the HIG keeps app-modal), NSPageLayout and NSPrintPanel.  Which parent:
 * the window a -runModalForWindow:relativeToWindow: names, else the window
 * whose close is in progress, else the key window, else (with no
 * key window) the main window.  During -terminate: only a window that is
 * closing, or that the application made key for the question: an
 * application-wide question ("You have unsaved documents") stays centered.
 */

#import <AppKit/AppKit.h>

#import "GBSheet.h"
#import "GBTheme.h"
#import "GBThemeHooks+Alert.h"

@interface NSApplication (GBAutoSheet)
- (NSModalSession)gb_beginModalSessionForWindow:(NSWindow *)window;
- (void)gb_endModalSession:(NSModalSession)session;
- (NSInteger)gb_runModalForWindow:(NSWindow *)window relativeToWindow:(NSWindow *)docWindow;
- (void)gb_terminate:(id)sender;
@end

/* Windows whose -performClose: (or document close check) is running, the
 * innermost last. */
static NSMutableArray *sClosingWindows = nil;

static NSUInteger sSuppressDepth = 0;
static NSUInteger sTerminateDepth = 0;
static __weak NSWindow *sTerminateKeyWindow = nil;
static __weak NSWindow *sPreferredParent = nil;

/* Modal sessions whose window was attached here, with that window. */
static NSMutableArray *sSessions = nil;
static NSMutableArray *sSessionWindows = nil;

static const void *kGBAlertPanelKey = &kGBAlertPanelKey;

BOOL GBAutoSheetsEnabled(void)
{
  id value;

  if (GBSheetsEnabled() == NO) {
    return NO;
  }
  value = [[NSUserDefaults standardUserDefaults] objectForKey:GBAutoSheetsDefault];
  return (value == nil) ? YES : [value boolValue];
}

void GBAutoSheetMarkAlertPanel(NSWindow *panel)
{
  if (panel != nil) {
    objc_setAssociatedObject(panel, kGBAlertPanelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
}

void GBAutoSheetPushClosingWindow(NSWindow *window)
{
  if (sClosingWindows == nil) {
    sClosingWindows = [NSMutableArray new];
  }
  /* A placeholder keeps pushes and pops paired when the closing object has
   * no window (a document without one). */
  [sClosingWindows addObject:(window != nil) ? (id)window : (id)[NSNull null]];
}

void GBAutoSheetPopClosingWindow(void)
{
  if ([sClosingWindows count] > 0) {
    [sClosingWindows removeLastObject];
  }
}

void GBAutoSheetSetSuppressed(BOOL suppressed)
{
  if (suppressed) {
    sSuppressDepth++;
  }
  else if (sSuppressDepth > 0) {
    sSuppressDepth--;
  }
}

void GBAutoSheetWindowMadeKey(NSWindow *window)
{
  /* Dialogs raising themselves are not what the question is about. */
  if (sTerminateDepth > 0 && [window isKindOfClass:[NSPanel class]] == NO) {
    sTerminateKeyWindow = window;
  }
}

static BOOL GBIsKindOfNamedClass(NSWindow *window, NSString *name)
{
  Class cls = NSClassFromString(name);

  return cls != Nil && [window isKindOfClass:cls];
}

static BOOL GBAutoSheetDialogQualifies(NSWindow *dialog)
{
  id theme;

  if (GBIsKindOfNamedClass(dialog, @"GSAlertPanel") ||
      objc_getAssociatedObject(dialog, kGBAlertPanelKey) != nil) {
    return YES;
  }
  /* A theme may build alert panels of its own class (Eau morphs
   * GSAlertPanel instances into an NSPanel subclass). */
  theme = GBThemeIfResponds(@selector(gbIsAlertPanel:));
  if (theme != nil && [theme gbIsAlertPanel:dialog]) {
    return YES;
  }
  if ([dialog isKindOfClass:[NSOpenPanel class]]) {
    return NO;
  }
  return [dialog isKindOfClass:[NSSavePanel class]] ||
         [dialog isKindOfClass:[NSPageLayout class]] || [dialog isKindOfClass:[NSPrintPanel class]];
}

static BOOL GBIsOnScreen(NSWindow *window)
{
  NSRect frame = [window frame];

  for (NSScreen *screen in [NSScreen screens]) {
    if (NSIntersectsRect(frame, [screen frame])) {
      return YES;
    }
  }
  return NO;
}

/* A document window a sheet can hang from: a plain titled window at the
 * normal level, shown, with no other sheet. */
static BOOL GBAutoSheetParentIsValid(NSWindow *parent, NSWindow *dialog)
{
  return parent != nil && parent != dialog && [parent windowNumber] != 0 && [parent isVisible] &&
         [parent isMiniaturized] == NO && ([parent styleMask] & NSTitledWindowMask) != 0 &&
         [parent isKindOfClass:[NSPanel class]] == NO && [parent level] == NSNormalWindowLevel &&
         GBSheetIsManaged(parent) == NO && [GBSheetSheetsOf(parent) count] == 0 &&
         [parent attachedSheet] == nil && GBIsOnScreen(parent);
}

NSWindow *GBAutoSheetParentFor(NSWindow *dialog)
{
  NSWindow *candidate = nil;
  id closing;

  if (dialog == nil || sSuppressDepth > 0 || GBAutoSheetsEnabled() == NO ||
      [NSApp modalWindow] != nil || [NSApp isActive] == NO || GBSheetIsManaged(dialog) ||
      GBAutoSheetDialogQualifies(dialog) == NO) {
    return nil;
  }

  closing = [sClosingWindows lastObject];
  if (sPreferredParent != nil) {
    candidate = sPreferredParent;
  }
  else if (closing != nil) {
    /* The dialog is about that window, even when another one is key; a
     * closing panel or window without one gets no sheet elsewhere. */
    candidate = (closing != [NSNull null]) ? closing : nil;
  }
  else if (sTerminateDepth > 0) {
    /* Quitting: only a window the application brought forward for this
     * question (reviewing unsaved documents one by one) is its subject. */
    NSWindow *reviewed = sTerminateKeyWindow;
    if (reviewed != nil && ([NSApp keyWindow] == reviewed || [NSApp mainWindow] == reviewed)) {
      candidate = reviewed;
    }
  }
  else {
    candidate = [NSApp keyWindow];
    if (candidate == dialog) {
      candidate = nil;
    }
    if (candidate == nil) {
      candidate = [NSApp mainWindow];
    }
  }
  return GBAutoSheetParentIsValid(candidate, dialog) ? candidate : nil;
}

@implementation NSApplication (GBAutoSheet)

+ (void)load
{
  Class cls = [NSApplication class];

  GBSheetSwizzle(cls, @selector(beginModalSessionForWindow:),
                 @selector(gb_beginModalSessionForWindow:));
  GBSheetSwizzle(cls, @selector(endModalSession:), @selector(gb_endModalSession:));
  GBSheetSwizzle(cls, @selector(runModalForWindow:relativeToWindow:),
                 @selector(gb_runModalForWindow:relativeToWindow:));
  GBSheetSwizzle(cls, @selector(terminate:), @selector(gb_terminate:));
}

/* The modal session is where every synchronous dialog passes (runModal,
 * runModalForWindow:, and code that runs its own session loop), and ending
 * it covers stop, abort and exceptions alike. */
- (NSModalSession)gb_beginModalSessionForWindow:(NSWindow *)window
{
  NSWindow *parent = GBAutoSheetParentFor(window);
  NSModalSession session;

  if (parent != nil) {
    GBSheetBegin(window, parent, nil, NULL, NULL, nil, NO);
    if (GBSheetIsActive(window) == NO) {
      GBSheetEnd(window, NSRunAbortedResponse);
      parent = nil;
    }
  }
  /* Attached first, the dialog is already visible here, so libs-gui does
   * not center it. */
  session = [self gb_beginModalSessionForWindow:window];
  if (parent != nil) {
    /* libs-gui lifts a modal panel to NSModalPanelWindowLevel, over every
     * other application; a sheet stays with its parent.  Ending the
     * session puts back this level, and ending the sheet the dialog's own. */
    [window setLevel:[parent level]];
    GBSheetPlace(window);
    if (sSessions == nil) {
      sSessions = [NSMutableArray new];
      sSessionWindows = [NSMutableArray new];
    }
    [sSessions addObject:[NSValue valueWithPointer:session]];
    [sSessionWindows addObject:window];
  }
  return session;
}

- (void)gb_endModalSession:(NSModalSession)session
{
  NSUInteger index = [sSessions indexOfObject:[NSValue valueWithPointer:session]];
  NSWindow *sheet = nil;

  if (index != NSNotFound) {
    sheet = [sSessionWindows objectAtIndex:index];
    [sSessions removeObjectAtIndex:index];
    [sSessionWindows removeObjectAtIndex:index];
  }
  [self gb_endModalSession:session];
  /* Ended earlier when its parent was closed from code. */
  if (sheet != nil) {
    GBSheetEnd(sheet, NSRunStoppedResponse);
  }
}

/* "Relative to" a window is what a sheet is: skip the centering on it. */
- (NSInteger)gb_runModalForWindow:(NSWindow *)window relativeToWindow:(NSWindow *)docWindow
{
  NSWindow *previous = sPreferredParent;
  NSInteger code;

  if (docWindow == nil || sSuppressDepth > 0) {
    return [self gb_runModalForWindow:window relativeToWindow:docWindow];
  }
  sPreferredParent = docWindow;
  if (GBAutoSheetParentFor(window) == nil) {
    sPreferredParent = previous;
    return [self gb_runModalForWindow:window relativeToWindow:docWindow];
  }
  @try {
    code = [self runModalForWindow:window];
  }
  @finally {
    sPreferredParent = previous;
  }
  return code;
}

- (void)gb_terminate:(id)sender
{
  NSWindow *previous = sTerminateKeyWindow;

  sTerminateDepth++;
  sTerminateKeyWindow = nil;
  @try {
    [self gb_terminate:sender];
  }
  @finally {
    sTerminateDepth--;
    sTerminateKeyWindow = previous;
  }
}

@end
