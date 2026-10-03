/* SheetTest - manual/scripted test for window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Interactive: a document window with buttons that put up sheets, and an
 * "Other Window" whose counter must keep working while a sheet is up.
 * With -autotest YES the same scenarios run scripted, each check logs
 * "SHEETTEST PASS|FAIL <what>", and the exit status is the failure count.
 * SHEETTEST_SNAPDIR=<dir> saves root-window screenshots (ImageMagick).
 *
 * The second half covers synchronous dialogs (GBAutoSheet.m): a plain
 * NSObject "document" whose -windowShouldClose: runs NSRunAlertPanel, NSAlert
 * and NSSavePanel -runModal, and the cases that must stay app-modal.  Their
 * checks run from a background thread that calls back into the main thread
 * in the modal run loop mode while the dialog blocks.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdlib.h>
#include <string.h>

/* Cocoa API that GershwinBehaviors adds to libs-gui at runtime. */
@interface NSWindow (SheetTestCocoaAPI)
- (void)endSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode;
@end

@interface TestDocument : NSDocument
@end

@implementation TestDocument
- (NSData *)dataOfType:(NSString *)type error:(NSError **)error
{
  return [NSData data];
}
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)type error:(NSError **)error
{
  return YES;
}
- (NSString *)displayName
{
  return @"Report.txt";
}
@end

/* A window delegate that is not an NSDocument, like TextEdit's Document:
 * the close question is a blocking NSRunAlertPanel. */
@interface PlainDocument : NSObject {
@public
  BOOL edited;
  NSInteger lastAnswer;
  BOOL asked;
}
@end

@implementation PlainDocument
- (BOOL)windowShouldClose:(id)sender
{
  if (!edited) {
    return YES;
  }
  asked = YES;
  lastAnswer =
      NSRunAlertPanel(@"Close", @"Save changes to Notes?", @"Save", @"Cancel", @"Don't Save");
  if (lastAnswer == NSAlertOtherReturn) {
    edited = NO;
    return YES;
  }
  return NO;
}
@end

/* WM_WINDOW_ROLE of the X window behind w, or nil. */
static NSString *WindowRole(NSWindow *w)
{
  GSDisplayServer *srv = GSServerForWindow(w);
  Display *dpy = (Display *)[srv serverDevice];
  Window xwin;
  Atom type = None;
  int format = 0;
  unsigned long n = 0;
  unsigned long after = 0;
  unsigned char *value = NULL;
  NSString *role = nil;

  if (dpy == NULL || [w windowNumber] == 0) {
    return nil;
  }
  xwin = (Window)(uintptr_t)[srv windowDevice:[w windowNumber]];
  if (XGetWindowProperty(dpy, xwin, XInternAtom(dpy, "WM_WINDOW_ROLE", False), 0, 16, False,
                         XA_STRING, &type, &format, &n, &after, &value) == Success &&
      value != NULL) {
    role = [[NSString alloc] initWithBytes:value
                                    length:strnlen((char *)value, n)
                                  encoding:NSISOLatin1StringEncoding];
  }
  if (value != NULL) {
    XFree(value);
  }
  return role;
}

@interface Controller : NSObject {
  NSWindow *docWindow;
  NSWindow *otherWindow;
  NSTextField *otherLabel;
  NSButton *otherButton;
  NSButton *editButton;
  NSButton *customButton;
  NSTimeInterval beginDuration;
  NSPanel *customSheet;
  NSPanel *secondSheet;
  TestDocument *document;
  NSInteger otherClicks;
  BOOL editClicked;
  BOOL callbackFired;
  NSInteger lastCode;
  NSUInteger originalStyle;
  NSMutableArray *steps;
  int failures;
  NSWindow *notesWindow;
  PlainDocument *plainDoc;
  NSPanel *utilityPanel;
  NSWindow *probed;
  NSUInteger probedStyle;
  NSInteger modalResult;
  BOOL quitTest;
  BOOL inProbe;
  NSString *pendingClick;
}
@end

static NSPanel *MakeSheet(NSString *text, id target, SEL action)
{
  NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 340, 110)
                                              styleMask:NSTitledWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:YES];
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 60, 300, 24)];
  NSButton *ok = [[NSButton alloc] initWithFrame:NSMakeRect(230, 16, 90, 28)];

  [panel setTitle:@"Sheet"];
  [panel setReleasedWhenClosed:NO];
  [label setStringValue:text];
  [label setEditable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [[panel contentView] addSubview:label];
  [ok setTitle:@"OK"];
  [ok setKeyEquivalent:@"\r"];
  [ok setTarget:target];
  [ok setAction:action];
  [[panel contentView] addSubview:ok];
  return panel;
}

static NSButton *FindButton(NSView *view, NSString *title)
{
  for (NSView *sub in [view subviews]) {
    if ([sub isKindOfClass:[NSButton class]] && [[(NSButton *)sub title] isEqualToString:title]) {
      return (NSButton *)sub;
    }
    NSButton *found = FindButton(sub, title);
    if (found != nil) {
      return found;
    }
  }
  return nil;
}

static NSString *AllText(NSView *view)
{
  NSMutableString *text = [NSMutableString string];

  if ([view isKindOfClass:[NSTextField class]]) {
    [text appendString:[(NSTextField *)view stringValue]];
  }
  for (NSView *sub in [view subviews]) {
    [text appendString:AllText(sub)];
  }
  return text;
}

@implementation Controller

- (void)check:(BOOL)ok what:(NSString *)what
{
  NSLog(@"SHEETTEST %@ %@", ok ? @"PASS" : @"FAIL", what);
  if (!ok) {
    failures++;
  }
}

- (void)snap:(NSString *)name
{
  const char *dir = getenv("SHEETTEST_SNAPDIR");

  if (dir != NULL) {
    NSString *cmd = [NSString stringWithFormat:@"import -window root '%s/%@.png'", dir, name];
    if (system([cmd UTF8String]) != 0) {
      NSLog(@"SHEETTEST snapshot %@ failed", name);
    }
  }
}

- (void)makeWindows
{
  NSButton *b;
  NSWindowController *wc;
  NSArray *titles = [NSArray arrayWithObjects:@"Custom Sheet", @"Alert Sheet", @"Two Sheets",
                                              @"Save Panel Sheet", @"Mark Edited", nil];
  SEL actions[] = { @selector(customSheet:), @selector(alertSheet:), @selector(twoSheets:),
                    @selector(savePanelSheet:), @selector(markEdited:) };
  NSUInteger i;

  docWindow =
      [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 200, 520, 360)
                                  styleMask:NSTitledWindowMask | NSClosableWindowMask |
                                            NSMiniaturizableWindowMask | NSResizableWindowMask
                                    backing:NSBackingStoreBuffered
                                      defer:NO];
  [docWindow setReleasedWhenClosed:NO];
  for (i = 0; i < [titles count]; i++) {
    b = [[NSButton alloc] initWithFrame:NSMakeRect(20, 300 - 40 * (CGFloat)i, 180, 28)];
    [b setTitle:[titles objectAtIndex:i]];
    [b setTarget:self];
    [b setAction:actions[i]];
    [[docWindow contentView] addSubview:b];
    if (actions[i] == @selector(markEdited:)) {
      editButton = b;
    }
    if (actions[i] == @selector(customSheet:)) {
      customButton = b;
    }
  }

  document = [[TestDocument alloc] init];
  wc = [[NSWindowController alloc] initWithWindow:docWindow];
  [document addWindowController:wc];
  [docWindow setTitle:@"Report.txt"];
  [docWindow makeKeyAndOrderFront:nil];

  otherWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(700, 300, 260, 120)
                                            styleMask:NSTitledWindowMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  [otherWindow setTitle:@"Other Window"];
  [otherWindow setReleasedWhenClosed:NO];
  otherButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 60, 140, 28)];
  [otherButton setTitle:@"Count"];
  [otherButton setTarget:self];
  [otherButton setAction:@selector(count:)];
  [[otherWindow contentView] addSubview:otherButton];
  otherLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 200, 24)];
  [otherLabel setEditable:NO];
  [otherLabel setStringValue:@"0 clicks"];
  [[otherWindow contentView] addSubview:otherLabel];
  [otherWindow orderFront:nil];

  customSheet = MakeSheet(@"A custom sheet; OK ends it with code 42.", self, @selector(endCustom:));
  secondSheet = MakeSheet(@"The queued second sheet.", self, @selector(endSecond:));
}

- (void)count:(id)sender
{
  otherClicks++;
  [otherLabel setStringValue:[NSString stringWithFormat:@"%ld clicks", (long)otherClicks]];
}

- (void)markEdited:(id)sender
{
  editClicked = YES;
  [document updateChangeCount:NSChangeDone];
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)info
{
  callbackFired = YES;
  lastCode = code;
  NSLog(@"SHEETTEST didEnd %@ code %ld", [sheet title], (long)code);
}

- (void)customSheet:(id)sender
{
  NSDate *start = [NSDate date];

  [NSApp beginSheet:customSheet
      modalForWindow:docWindow
       modalDelegate:self
      didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
         contextInfo:NULL];
  beginDuration = -[start timeIntervalSinceNow];
}

- (void)endCustom:(id)sender
{
  [NSApp endSheet:customSheet returnCode:42];
}

- (void)endSecond:(id)sender
{
  [NSApp endSheet:secondSheet returnCode:43];
}

- (void)alertSheet:(id)sender
{
  NSAlert *alert = [[NSAlert alloc] init];

  [alert setMessageText:@"An alert as a sheet"];
  [alert setInformativeText:@"The Other Window keeps working meanwhile."];
  [alert addButtonWithTitle:@"First"];
  [alert addButtonWithTitle:@"Second"];
  [alert beginSheetModalForWindow:docWindow
                completionHandler:^(NSModalResponse code) {
                  callbackFired = YES;
                  lastCode = code;
                  NSLog(@"SHEETTEST alert ended %ld", (long)code);
                }];
}

- (void)twoSheets:(id)sender
{
  [self customSheet:sender];
  [docWindow beginSheet:secondSheet
      completionHandler:^(NSModalResponse code) {
        callbackFired = YES;
        lastCode = code;
      }];
}

- (void)savePanelSheet:(id)sender
{
  NSSavePanel *panel = [NSSavePanel savePanel];

  [panel beginSheetModalForWindow:docWindow
                completionHandler:^(NSInteger code) {
                  callbackFired = YES;
                  lastCode = code;
                  NSLog(@"SHEETTEST save panel ended %ld", (long)code);
                }];
}

/* A real click through the X server, so the event takes the same path as
 * a user's (and button tracking, which re-reads the pointer, agrees). */
- (void)clickView:(NSView *)view
{
  NSWindow *w = [view window];
  NSPoint p = [view convertPoint:NSMakePoint(NSMidX([view bounds]), NSMidY([view bounds]))
                          toView:nil];
  NSPoint s = [w convertBaseToScreen:p];
  CGFloat screenHeight = NSHeight([[NSScreen mainScreen] frame]);
  NSString *cmd = [NSString
      stringWithFormat:@"xdotool mousemove %d %d click 1", (int)s.x, (int)(screenHeight - s.y)];

  /* From a probe the click is sent by the probe thread once the main
   * thread is back in the modal loop: sent from inside the loop's callback
   * it is sometimes lost. */
  if (view != nil && inProbe) {
    pendingClick = cmd;
    return;
  }
  if (view == nil || system([cmd UTF8String]) != 0) {
    NSLog(@"SHEETTEST could not click %@", view);
  }
}

- (void)checkPlacementOf:(NSWindow *)sheet what:(NSString *)what
{
  [self checkPlacementOf:sheet parent:docWindow what:what];
}

- (void)checkPlacementOf:(NSWindow *)sheet parent:(NSWindow *)parent what:(NSString *)what
{
  NSRect pf = [parent frame];
  NSRect sf = [sheet frame];
  CGFloat top = NSMinY(pf) + NSMaxY([[parent contentView] frame]);

  [self check:fabs(NSMaxY(sf) - top) <= 1.0
         what:[NSString stringWithFormat:@"%@ top %.0f at parent content top %.0f", what,
                                         NSMaxY(sf), top]];
  [self check:fabs(NSMidX(sf) - NSMidX(pf)) <= 1.0
         what:[NSString
                  stringWithFormat:@"%@ centered (%.0f vs %.0f)", what, NSMidX(sf), NSMidX(pf)]];
}

- (void)runBlock:(void (^)(void))block
{
  inProbe = YES;
  block();
  inProbe = NO;
}

- (void)probeThread:(NSArray *)args
{
  @autoreleasepool {
    [NSThread sleepForTimeInterval:[[args objectAtIndex:0] doubleValue]];
    [self performSelectorOnMainThread:@selector(runBlock:)
                           withObject:[args objectAtIndex:1]
                        waitUntilDone:YES
                                modes:[NSArray arrayWithObjects:NSDefaultRunLoopMode,
                                                                NSModalPanelRunLoopMode,
                                                                NSEventTrackingRunLoopMode, nil]];
    NSString *cmd = pendingClick;
    pendingClick = nil;
    if (cmd != nil && system([cmd UTF8String]) != 0) {
      NSLog(@"SHEETTEST could not run %@", cmd);
    }
  }
}

/* Runs block on the main thread after delay, also while a modal session
 * (the dialog under test) blocks it; timers of the default mode would not
 * fire there. */
- (void)probeAfter:(NSTimeInterval)delay do:(void (^)(void))block
{
  [NSThread detachNewThreadSelector:@selector(probeThread:)
                           toTarget:self
                         withObject:[NSArray arrayWithObjects:[NSNumber numberWithDouble:delay],
                                                              [block copy], nil]];
}

/* The running modal dialog hangs from parent as a sheet. */
- (void)checkAutoSheetOn:(NSWindow *)parent what:(NSString *)what
{
  NSWindow *dialog = [NSApp modalWindow];

  probed = dialog;
  [self check:dialog != nil && [parent attachedSheet] == dialog && [dialog sheetParent] == parent
         what:[NSString stringWithFormat:@"%@: attached as a sheet (%@)", what, dialog]];
  [self check:[dialog styleMask] == NSBorderlessWindowMask
         what:[NSString stringWithFormat:@"%@: sheet is borderless", what]];
  [self
      check:[WindowRole(dialog) isEqualToString:@"sheet"]
       what:[NSString stringWithFormat:@"%@: WM_WINDOW_ROLE sheet (%@)", what, WindowRole(dialog)]];
  [self check:[dialog level] == [parent level]
         what:[NSString stringWithFormat:@"%@: sheet at its parent's level (%ld)", what,
                                         (long)[dialog level]]];
  [self checkPlacementOf:dialog parent:parent what:what];
}

/* The running modal dialog is an ordinary centered panel. */
- (void)checkCenteredWhat:(NSString *)what
{
  NSWindow *dialog = [NSApp modalWindow];
  NSRect screen = [[NSScreen mainScreen] visibleFrame];

  probed = dialog;
  [self check:dialog != nil && [dialog sheetParent] == nil &&
              ([dialog styleMask] & NSTitledWindowMask) != 0 &&
              ![WindowRole(dialog) isEqualToString:@"sheet"]
         what:[NSString stringWithFormat:@"%@: stays an app-modal panel (%@)", what, dialog]];
  [self check:fabs(NSMidX([dialog frame]) - NSMidX(screen)) <= 2.0
         what:[NSString stringWithFormat:@"%@: centered on the screen (%.0f vs %.0f)", what,
                                         NSMidX([dialog frame]), NSMidX(screen)]];
}

/* After the session: the dialog is back to what it was. */
- (void)checkRestored:(NSWindow *)parent what:(NSString *)what
{
  [self check:probed != nil && ![probed isVisible] && [probed sheetParent] == nil &&
              [parent attachedSheet] == nil && [probed styleMask] == probedStyle &&
              ![WindowRole(probed) isEqualToString:@"sheet"]
         what:[NSString stringWithFormat:@"%@: dialog detached, style %lu restored", what,
                                         (unsigned long)[probed styleMask]]];
}

/* -stopModalWithCode: from code (not from an event) only takes effect
 * when the modal loop sees its next event. */
- (void)cancelModalPanel
{
  [(NSSavePanel *)[NSApp modalWindow] cancel:nil];
  [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0]
           atStart:NO];
}

- (void)clickButton:(NSString *)title
{
  NSButton *button = FindButton([[NSApp modalWindow] contentView], title);

  [self check:button != nil what:[NSString stringWithFormat:@"button %@ found", title]];
  [self clickView:button];
}

- (void)makeNotesWindow
{
  notesWindow = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(160, 220, 520, 340)
                styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                  backing:NSBackingStoreBuffered
                    defer:NO];
  [notesWindow setTitle:@"Notes"];
  [notesWindow setReleasedWhenClosed:NO];
  plainDoc = [PlainDocument new];
  [notesWindow setDelegate:(id)plainDoc];
  [notesWindow makeKeyAndOrderFront:nil];

  utilityPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(760, 500, 240, 120)
                                            styleMask:NSTitledWindowMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  [utilityPanel setTitle:@"Inspector"];
  [utilityPanel setReleasedWhenClosed:NO];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app
{
  __weak Controller *weakSelf = self;
  NSInteger choice;

  if (!quitTest) {
    return NSTerminateNow;
  }
  quitTest = NO;
  /* Asked about the whole application, like TextEdit's "You have unsaved
   * documents": no window is its subject. */
  [self probeAfter:1.5
                do:^{
                  Controller *c = weakSelf;
                  [c checkCenteredWhat:@"quit: app-wide question"];
                  [c snap:@"7-quit-app-wide"];
                  [c clickButton:@"Review Unsaved"];
                }];
  choice = NSRunAlertPanel(@"Quit", @"You have unsaved documents.", @"Review Unsaved",
                           @"Quit Anyway", @"Cancel");
  [self check:choice == NSAlertDefaultReturn
         what:[NSString stringWithFormat:@"quit: app-wide answer Review (%ld)", (long)choice]];
  /* Reviewing: each document window is brought forward, then asked about. */
  [notesWindow makeKeyAndOrderFront:nil];
  [self probeAfter:1.5
                do:^{
                  Controller *c = weakSelf;
                  [c checkAutoSheetOn:c->notesWindow what:@"quit: per-document question"];
                  [c snap:@"8-quit-per-document"];
                  [c clickButton:@"Cancel"];
                }];
  choice = NSRunAlertPanel(@"Close", @"Save changes to Notes?", @"Save", @"Cancel", @"Don't Save");
  [self check:choice == NSAlertAlternateReturn
         what:[NSString stringWithFormat:@"quit: per-document answer Cancel (%ld)", (long)choice]];
  return NSTerminateCancel;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app
{
  return NO;
}

- (void)queueAutoSheetSteps
{
  __weak Controller *weakSelf = self;

  /* TextEdit's case: -windowShouldClose: of a plain NSObject delegate runs
   * NSRunAlertPanel.  Cancel keeps the window. */
  [steps addObject:^{
    Controller *c = weakSelf;
    [c makeNotesWindow];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    c->plainDoc->edited = YES;
    c->probed = nil;
    [c probeAfter:1.5
               do:^{
                 [c checkAutoSheetOn:c->notesWindow
                                what:@"NSRunAlertPanel from windowShouldClose:"];
                 [c snap:@"5-runalertpanel-sheet"];
                 [c clickButton:@"Cancel"];
               }];
    [c->notesWindow performClose:nil];
    [c check:c->plainDoc->asked && c->plainDoc->lastAnswer == NSAlertAlternateReturn
        what:[NSString stringWithFormat:@"NSRunAlertPanel returns Cancel synchronously (%ld)",
                                        (long)c->plainDoc->lastAnswer]];
    c->probedStyle = [c->probed styleMask];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    /* The panel's style was read back after the session, so compare with
     * a titled panel: GSAlertPanel and Eau's are titled and closable. */
    [c check:(c->probedStyle & NSTitledWindowMask) != 0
        what:[NSString stringWithFormat:@"alert panel titled again (%lu)",
                                        (unsigned long)c->probedStyle]];
    [c checkRestored:c->notesWindow what:@"after Cancel"];
    [c check:[c->notesWindow isVisible] && [NSApp keyWindow] == c->notesWindow
        what:@"Cancel keeps the window, key again"];
    [c snap:@"5b-after-cancel"];
    c->plainDoc->asked = NO;
    [c probeAfter:1.5
               do:^{
                 [c checkAutoSheetOn:c->notesWindow what:@"second close question"];
                 [c clickButton:@"Don't Save"];
               }];
    [c->notesWindow performClose:nil];
    [c check:c->plainDoc->lastAnswer == NSAlertOtherReturn && ![c->notesWindow isVisible]
        what:[NSString stringWithFormat:@"Don't Save (%ld) closes the window",
                                        (long)c->plainDoc->lastAnswer]];
  }];

  /* NSAlert -runModal with a document window key. */
  [steps addObject:^{
    Controller *c = weakSelf;
    [c->notesWindow makeKeyAndOrderFront:nil];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSAlert *alert = [[NSAlert alloc] init];
    NSInteger code;
    [alert setMessageText:@"A modal NSAlert"];
    [alert setInformativeText:@"runModal with a key document window."];
    [alert addButtonWithTitle:@"First"];
    [alert addButtonWithTitle:@"Second"];
    c->probed = nil;
    [c probeAfter:1.5
               do:^{
                 c->probedStyle = NSTitledWindowMask;
                 [c checkAutoSheetOn:c->notesWindow what:@"NSAlert runModal"];
                 [c snap:@"6-nsalert-runmodal-sheet"];
                 [c clickButton:@"Second"];
               }];
    code = [alert runModal];
    [c check:code == NSAlertSecondButtonReturn
        what:[NSString stringWithFormat:@"NSAlert runModal returns Second (%ld)", (long)code]];
    [c check:c->probed != nil && ![c->probed isVisible] && [c->notesWindow attachedSheet] == nil &&
             ([c->probed styleMask] & NSTitledWindowMask) != 0
        what:@"NSAlert panel detached and titled again"];
  }];

  /* NSSavePanel -runModal becomes a sheet, NSOpenPanel does not. */
  [steps addObject:^{
    Controller *c = weakSelf;
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSInteger code;
    c->probedStyle = [panel styleMask];
    c->probed = nil;
    [c probeAfter:2.0
               do:^{
                 [c checkAutoSheetOn:c->notesWindow what:@"NSSavePanel runModal"];
                 [c snap:@"9-savepanel-runmodal-sheet"];
                 [c cancelModalPanel];
               }];
    code = [panel runModal];
    [c check:code == NSCancelButton
        what:[NSString stringWithFormat:@"save panel runModal returns Cancel (%ld)", (long)code]];
    [c checkRestored:c->notesWindow what:@"save panel"];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    NSInteger code;
    [c probeAfter:2.0
               do:^{
                 [c check:[c->notesWindow attachedSheet] == nil
                     what:@"NSOpenPanel runModal is not a sheet"];
                 [c checkCenteredWhat:@"NSOpenPanel runModal"];
                 [c cancelModalPanel];
               }];
    code = [panel runModal];
    [c check:code == NSCancelButton
        what:[NSString stringWithFormat:@"open panel runModal returns Cancel (%ld)", (long)code]];
  }];

  /* A utility panel is key: no document window is the subject. */
  [steps addObject:^{
    Controller *c = weakSelf;
    [c->utilityPanel makeKeyAndOrderFront:nil];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSInteger code;
    [c probeAfter:1.5
               do:^{
                 [c checkCenteredWhat:@"alert with a panel key"];
                 [c snap:@"10-no-parent-centered"];
                 [c clickButton:@"OK"];
               }];
    code = NSRunAlertPanel(@"Inspector", @"Nothing selected.", @"OK", nil, nil);
    [c check:code == NSAlertDefaultReturn
        what:[NSString stringWithFormat:@"centered alert returns OK (%ld)", (long)code]];
    [c->utilityPanel orderOut:nil];
    [c->notesWindow makeKeyAndOrderFront:nil];
  }];

  /* Quitting: the app-wide question stays centered, the per-document one
   * attaches to the window the application brought forward. */
  [steps addObject:^{
    Controller *c = weakSelf;
    c->quitTest = YES;
    [NSApp terminate:nil];
    [c check:c->quitTest == NO && [c->notesWindow isVisible] what:@"terminate cancelled"];
  }];

  /* GBAutoSheets NO: exactly the old behavior. */
  [steps addObject:^{
    Controller *c = weakSelf;
    NSInteger code;
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"GBAutoSheets"];
    [c->notesWindow makeKeyAndOrderFront:nil];
    [c probeAfter:1.5
               do:^{
                 [c checkCenteredWhat:@"GBAutoSheets NO"];
                 [c snap:@"11-autosheets-off"];
                 [c clickButton:@"OK"];
               }];
    code = NSRunAlertPanel(@"Close", @"GBAutoSheets is NO.", @"OK", nil, nil);
    [c check:code == NSAlertDefaultReturn && [c->notesWindow attachedSheet] == nil
        what:@"GBAutoSheets NO keeps the alert app-modal"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"GBAutoSheets"];
  }];
}

- (void)queueAutotest
{
  __weak Controller *weakSelf = self;
  /* xdotool clicks reach the app only once its run loop next wakes up, so
   * a click step is followed by an idle one before anything is checked. */
  void (^idle)(void) = ^{
  };
  steps = [NSMutableArray array];

  /* -autosheets YES: only the synchronous-dialog half. */
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"autosheets"]) {
    [self queueAutoSheetSteps];
    return;
  }
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"GBWindowModalSheets"] != nil &&
      [[NSUserDefaults standardUserDefaults] boolForKey:@"GBWindowModalSheets"] == NO) {
    /* The blocking libs-gui beginSheet already ran at launch (see
     * -applicationDidFinishLaunching:); only its outcome is checked. */
    [steps addObject:^{
      Controller *c = weakSelf;
      [c check:c->beginDuration >= 1.0 && c->callbackFired && c->lastCode == 42
          what:[NSString stringWithFormat:
                             @"kill switch: beginSheet blocked %.1fs app-modal like libs-gui",
                             c->beginDuration]];
    }];
    return;
  }

  [steps addObject:^{
    Controller *c = weakSelf;
    NSDate *start = [NSDate date];
    c->originalStyle = [c->customSheet styleMask];
    c->callbackFired = NO;
    [c customSheet:nil];
    NSTimeInterval took = -[start timeIntervalSinceNow];
    [c check:took < 0.3
        what:[NSString stringWithFormat:@"beginSheet returns immediately (%.2fs)", took]];
    [c check:[c->docWindow attachedSheet] == c->customSheet what:@"attachedSheet"];
    [c check:[c->customSheet sheetParent] == c->docWindow what:@"sheetParent"];
    [c check:[c->customSheet styleMask] == NSBorderlessWindowMask what:@"sheet is borderless"];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c snap:@"1-custom-sheet"];
    [c checkPlacementOf:c->customSheet what:@"custom sheet"];
    [c check:[c->customSheet isVisible] what:@"sheet visible"];
    [c clickView:c->editButton];
  }];
  [steps addObject:idle];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->editClicked == NO what:@"parent content ignores clicks"];
    [c clickView:c->otherButton];
  }];
  [steps addObject:idle];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->otherClicks == 1 what:@"other window still takes clicks"];
    [c->docWindow performClose:nil];
    [c->docWindow performMiniaturize:nil];
    [c check:[c->docWindow isVisible] && ![c->docWindow isMiniaturized]
        what:@"parent close/miniaturize refused"];
    [c->docWindow setFrame:NSOffsetRect([c->docWindow frame], 40, -30) display:YES];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c checkPlacementOf:c->customSheet what:@"sheet follows moved parent"];
    [c endCustom:nil];
    [c check:c->callbackFired == NO what:@"didEnd not called synchronously"];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->callbackFired && c->lastCode == 42 what:@"didEnd with code 42"];
    [c check:![c->customSheet isVisible] && [c->docWindow attachedSheet] == nil
        what:@"sheet ordered out and detached"];
    [c check:[c->customSheet styleMask] == c->originalStyle what:@"style restored"];
    c->callbackFired = NO;
    [c alertSheet:nil];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSWindow *sheet = [c->docWindow attachedSheet];
    [c snap:@"2-alert-sheet"];
    [c check:sheet != nil what:@"NSAlert beginSheetModalForWindow: attaches a sheet"];
    [c checkPlacementOf:sheet what:@"alert sheet"];
    [c clickView:FindButton([sheet contentView], @"Second")];
  }];
  [steps addObject:idle];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->callbackFired && c->lastCode == NSAlertSecondButtonReturn
        what:[NSString stringWithFormat:@"alert completion with Second (%ld)", (long)c->lastCode]];
    [c check:[c->docWindow attachedSheet] == nil what:@"alert sheet detached"];
    [c twoSheets:nil];
    [c check:[c->docWindow attachedSheet] == c->customSheet && ![c->secondSheet isVisible]
        what:@"second sheet queued"];
    [NSApp endSheet:c->customSheet returnCode:42];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:[c->docWindow attachedSheet] == c->secondSheet && [c->secondSheet isVisible]
        what:@"queued sheet shown after the first"];
    [c->docWindow endSheet:c->secondSheet returnCode:43];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->lastCode == 43 && [c->docWindow attachedSheet] == nil
        what:@"-[NSWindow endSheet:returnCode:] ends a completion-handler sheet"];
    c->callbackFired = NO;
    [c savePanelSheet:nil];
    [c check:[[c->docWindow attachedSheet] isKindOfClass:[NSSavePanel class]]
        what:@"NSSavePanel beginSheetModalForWindow: attaches a sheet"];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c snap:@"4-save-panel-sheet"];
    [(NSSavePanel *)[c->docWindow attachedSheet] cancel:nil];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:c->callbackFired && c->lastCode == NSCancelButton &&
             [c->docWindow attachedSheet] == nil
        what:@"save panel Cancel ends the sheet with NSCancelButton"];
    [c->document updateChangeCount:NSChangeDone];
    [c->docWindow performClose:nil];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSWindow *sheet = [c->docWindow attachedSheet];
    [c snap:@"3-save-changes-sheet"];
    [c check:[AllText([sheet contentView]) rangeOfString:@"Do you want to save"].location !=
             NSNotFound
        what:@"close of edited document asks in a sheet"];
    [c clickView:FindButton([sheet contentView], @"Cancel")];
  }];
  [steps addObject:idle];
  [steps addObject:^{
    Controller *c = weakSelf;
    NSEvent *cmdD;
    NSWindow *sheet;
    [c check:[c->docWindow isVisible] && [c->document isDocumentEdited]
        what:@"Cancel keeps the document open"];
    [c->docWindow performClose:nil];
    sheet = [c->docWindow attachedSheet];
    [sheet makeKeyWindow];
    cmdD = [NSEvent keyEventWithType:NSKeyDown
                            location:NSZeroPoint
                       modifierFlags:NSCommandKeyMask
                           timestamp:0
                        windowNumber:[sheet windowNumber]
                             context:nil
                          characters:@"d"
         charactersIgnoringModifiers:@"d"
                           isARepeat:NO
                             keyCode:40];
    [NSApp sendEvent:cmdD];
  }];
  [steps addObject:^{
    Controller *c = weakSelf;
    [c check:![c->docWindow isVisible] what:@"Command-D (Don't Save) closes the window"];
  }];
  [self queueAutoSheetSteps];
}

- (void)runNextStep
{
  if ([steps count] == 0) {
    NSLog(@"SHEETTEST DONE failures=%d", failures);
    exit(failures);
  }
  void (^step)(void) = [steps objectAtIndex:0];
  [steps removeObjectAtIndex:0];
  step();
  [self performSelector:@selector(runNextStep) withObject:nil afterDelay:1.2];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
  [self makeWindows];
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"autotest"]) {
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"GBWindowModalSheets"] != nil &&
        [[NSUserDefaults standardUserDefaults] boolForKey:@"GBWindowModalSheets"] == NO) {
      /* Return presses the sheet's OK once the modal loop runs; a real
       * key press because timers of that loop do not fire here. */
      if (system("(sleep 1.5; xdotool key Return) &") != 0) {
        NSLog(@"SHEETTEST could not schedule key press");
      }
      [self customSheet:nil];
    }
    [self queueAutotest];
    [self performSelector:@selector(runNextStep) withObject:nil afterDelay:1.0];
  }
}

@end

int main(int argc, const char **argv)
{
  @autoreleasepool {
    Controller *controller;

    [NSApplication sharedApplication];
    controller = [Controller new];
    [NSApp setDelegate:(id)controller];
    [NSApp run];
  }
  return 0;
}
