/* SheetTest - manual/scripted test for window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Interactive: a document window with buttons that put up sheets, and an
 * "Other Window" whose counter must keep working while a sheet is up.
 * With -autotest YES the same scenarios run scripted, each check logs
 * "SHEETTEST PASS|FAIL <what>", and the exit status is the failure count.
 * SHEETTEST_SNAPDIR=<dir> saves root-window screenshots (ImageMagick).
 */

#import <AppKit/AppKit.h>
#include <stdlib.h>

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

  if (view == nil || system([cmd UTF8String]) != 0) {
    NSLog(@"SHEETTEST could not click %@", view);
  }
}

- (void)checkPlacementOf:(NSWindow *)sheet what:(NSString *)what
{
  NSRect pf = [docWindow frame];
  NSRect sf = [sheet frame];
  CGFloat top = NSMinY(pf) + NSMaxY([[docWindow contentView] frame]);

  [self check:fabs(NSMaxY(sf) - top) <= 1.0
         what:[NSString stringWithFormat:@"%@ top %.0f at parent content top %.0f", what,
                                         NSMaxY(sf), top]];
  [self check:fabs(NSMidX(sf) - NSMidX(pf)) <= 1.0
         what:[NSString
                  stringWithFormat:@"%@ centered (%.0f vs %.0f)", what, NSMidX(sf), NSMidX(pf)]];
}

- (void)queueAutotest
{
  __weak Controller *weakSelf = self;
  /* xdotool clicks reach the app only once its run loop next wakes up, so
   * a click step is followed by an idle one before anything is checked. */
  void (^idle)(void) = ^{
  };
  steps = [NSMutableArray array];

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
