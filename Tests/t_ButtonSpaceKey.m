/* t_ButtonSpaceKey.m - ObjectTesting coverage for keyboard activation of
 * buttons under the Eau theme.
 *
 * The rules proven here (behavioral spec, gershwin-eau-theme):
 *
 *  1. Space clicks the button that has the keyboard focus, never the
 *     window's default button.
 *  2. Return still clicks the default button while another button has the
 *     keyboard focus.
 *  3. Rule 1 holds in the theme's modal alert panel too.
 *
 * Events travel through -[NSApplication sendEvent:] so the key equivalent
 * pass over the window runs exactly as for a real key press.
 *
 * Run with the theme under test, on a scratch display:
 *   DISPLAY=:97 ./obj/t_ButtonSpaceKey -GSTheme $PWD/../Eau.theme
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "NSAlert+Eau.h"

/* Longer than a tagged small string: a file whose string literals all fit
 * into tagged pointers emits no constant string section, and the runtime's
 * section bounds then fail to link. */
static NSString * const kDefaultTitle = @"Default button of the window";

@interface ClickRecorder : NSObject
{
@public
  NSMutableArray *clicks;
}
- (void) clicked: (id)sender;
@end

@implementation ClickRecorder
- (id) init
{
  if ((self = [super init]) != nil)
    {
      clicks = [NSMutableArray new];
    }
  return self;
}
- (void) clicked: (id)sender
{
  [clicks addObject: [sender title]];
}
@end

static NSButton *makeButton(NSString *title, NSRect frame,
                            ClickRecorder *recorder)
{
  NSButton *button = [[NSButton alloc] initWithFrame: frame];
  [button setTitle: title];
  [button setTarget: recorder];
  [button setAction: @selector(clicked:)];
  return button;
}

/* The panel class lives in the theme bundle, which is loaded at run time. */
static NSButton *alertButton(EauAlertPanel *panel, const char *name)
{
  return object_getIvar(panel,
                        class_getInstanceVariable([panel class], name));
}

static void pressKey(NSWindow *window, NSString *chars, unsigned short code)
{
  NSEvent *down = [NSEvent keyEventWithType: NSKeyDown
                                   location: NSZeroPoint
                              modifierFlags: 0
                                  timestamp: 0
                               windowNumber: [window windowNumber]
                                    context: nil
                                 characters: chars
                charactersIgnoringModifiers: chars
                                  isARepeat: NO
                                    keyCode: code];
  [NSApp sendEvent: down];
}

int main(void)
{
  @autoreleasepool {
    [NSApplication sharedApplication];

    ClickRecorder *recorder = [ClickRecorder new];
    NSWindow *window = [[NSWindow alloc]
      initWithContentRect: NSMakeRect(100, 100, 300, 100)
                styleMask: NSTitledWindowMask
                  backing: NSBackingStoreBuffered
                    defer: NO];
    NSButton *other = makeButton(@"Other", NSMakeRect(20, 20, 100, 24),
                                 recorder);
    NSButton *ok = makeButton(kDefaultTitle, NSMakeRect(180, 20, 100, 24), recorder);
    [ok setKeyEquivalent: @"\r"];
    [[window contentView] addSubview: other];
    [[window contentView] addSubview: ok];
    [window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];

    NSString *themeName = [[GSTheme theme] name];
    PASS([themeName isEqualToString: @"Eau"], "Eau theme is active (%s)",
         [themeName UTF8String]);
    PASS([window defaultButtonCell] == [ok cell], "OK is the default button");
    PASS([window makeFirstResponder: other], "Other takes the keyboard focus");

    /* --- 1. Space clicks the focused button --- */
    [recorder->clicks removeAllObjects];
    pressKey(window, @" ", 65);
    NSArray *onlyOther = [NSArray arrayWithObject: @"Other"];
    PASS_EQUAL(recorder->clicks, onlyOther,
               "Space clicks the focused button, not the default button");

    /* --- 2. Return still clicks the default button --- */
    [recorder->clicks removeAllObjects];
    pressKey(window, @"\r", 36);
    NSArray *onlyOK = [NSArray arrayWithObject: kDefaultTitle];
    PASS_EQUAL(recorder->clicks, onlyOK,
               "Return clicks the default button while another has focus");

    /* --- 3. Space in the alert panel clicks the focused button --- */
    EauAlertPanel *panel = [[NSClassFromString(@"EauAlertPanel") alloc] init];
    [panel setTitleBar: @"" icon: nil title: @"Replace the existing file?"
               message: @"Space must answer with the focused button."
                   def: @"Replace" alt: @"Cancel" other: @"Keep Both"];
    NSModalSession session = [NSApp beginModalSessionForWindow: panel];
    NSButton *alt = alertButton(panel, "altButton");
    PASS([panel makeFirstResponder: alt], "Cancel takes the keyboard focus");
    pressKey(panel, @" ", 65);
    PASS([panel result] == [alt tag],
         "Space in an alert clicks the focused button (result %ld, want %ld)",
         (long)[panel result], (long)[alt tag]);
    [NSApp endModalSession: session];
  }
  return 0;
}
