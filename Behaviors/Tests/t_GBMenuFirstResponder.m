/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* ObjectTesting coverage for menu items without a target (wired to the First
 * Responder) chosen in Menu.app: the action must reach the responder chain of
 * the key window, and the enabled flags sent to Menu.app must come from that
 * chain (gershwin-eau-theme#31).  Needs an X display; run with
 * -GSTheme GNUstep so the Eau theme bundle is not loaded on top. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GBMenuClient.h"

@interface GBMenuClient (TestedPrivate)
- (NSNumber *)_windowIdentifierForWindow:(NSWindow *)window;
- (NSDictionary *)_serializeMenu:(NSMenu *)menu;
@end

@interface FRView : NSView
{
@public
  int customCount;
  int copyCount;
  BOOL mode;
}
@end

@implementation FRView
- (BOOL) acceptsFirstResponder { return YES; }
- (void) customAction: (id)sender { customCount++; }
- (void) copy: (id)sender { copyCount++; }
- (void) toggleMode: (id)sender { mode = !mode; }
- (BOOL) validateMenuItem: (NSMenuItem *)item
{
  if ([item action] == @selector(toggleMode:))
    [item setState: mode ? NSOnState : NSOffState];
  return YES;
}
@end

/* Stands in for Menu.app and keeps the last enabled/state push. */
@interface FRServer : NSObject
{
@public
  NSDictionary *lastStates;
}
@end

@implementation FRServer
- (oneway void) updateMenuEnabledStatesForWindow: (NSNumber *)windowId
                                        menuData: (NSDictionary *)menuData
                                      clientName: (NSString *)clientName
{
  ASSIGN(lastStates, menuData);
}
- (oneway void) updateApplicationMenuEnabledStates: (NSDictionary *)menuData
                                        clientName: (NSString *)clientName
{
}
@end

@interface FRDelegate : NSObject
{
@public
  int delegateCount;
}
@end

@implementation FRDelegate
- (void) delegateAction: (id)sender { delegateCount++; }
@end

static void spin(void)
{
  [[NSRunLoop currentRunLoop]
    runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
}

static BOOL enabledIn(NSDictionary *menuData, NSUInteger top, NSUInteger idx)
{
  NSDictionary *sub = [[[menuData objectForKey: @"items"] objectAtIndex: top]
                        objectForKey: @"submenu"];
  return [[[[sub objectForKey: @"items"] objectAtIndex: idx]
            objectForKey: @"enabled"] boolValue];
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  [NSApp finishLaunching];

  NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
  NSMenuItem *edit = (NSMenuItem *)[main addItemWithTitle: @"Edit" action: NULL keyEquivalent: @""];
  NSMenu *sub = [[NSMenu alloc] initWithTitle: @"Edit"];
  [sub addItemWithTitle: @"Custom" action: @selector(customAction:) keyEquivalent: @""];
  [sub addItemWithTitle: @"Copy" action: @selector(copy:) keyEquivalent: @"c"];
  [sub addItemWithTitle: @"Delegate" action: @selector(delegateAction:) keyEquivalent: @""];
  [sub addItemWithTitle: @"Nobody" action: @selector(nobodyAction:) keyEquivalent: @""];
  [sub addItemWithTitle: @"Mode" action: @selector(toggleMode:) keyEquivalent: @"2"];
  [main setSubmenu: sub forItem: edit];
  [NSApp setMainMenu: main];
  /* AppKit may put an application menu in front of ours. */
  NSUInteger e = [main indexOfItem: edit];
  NSNumber *E = [NSNumber numberWithUnsignedInteger: e];

  NSWindow *win = [[NSWindow alloc]
    initWithContentRect: NSMakeRect(100, 100, 200, 100)
              styleMask: NSTitledWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  FRView *view = [[FRView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
  FRDelegate *delegate = [FRDelegate new];
  [win setContentView: view];
  [win setDelegate: (id)delegate];
  [NSApp activateIgnoringOtherApps: YES];
  [win makeKeyAndOrderFront: nil];
  spin();
  [win makeFirstResponder: view];

  PASS([NSApp keyWindow] == win, "test window is key");
  PASS([win firstResponder] == view, "test view is first responder");

  /* Not -init: that would register with the user's live Menu.app. */
  GBMenuClient *client = [GBMenuClient alloc];
  NSMutableDictionary *menus = [NSMutableDictionary dictionary];
  [client setValue: menus forKey: @"menuByWindowId"];
  NSNumber *wid = [client _windowIdentifierForWindow: win];
  PASS(wid != nil, "window has an identifier");
  [menus setObject: main forKey: wid];

  NSDictionary *data = [client _serializeMenu: main];
  PASS(enabledIn(data, e, 0), "first responder action is sent as enabled");
  PASS(enabledIn(data, e, 1), "copy: of the first responder is sent as enabled");
  PASS(enabledIn(data, e, 2), "window delegate action is sent as enabled");
  PASS(!enabledIn(data, e, 3), "action nobody implements is sent as disabled");

  [client activateMenuItemAtPath: @[E, @0] forWindow: wid];
  PASS(view->customCount == 1, "custom action reaches the first responder");
  [client activateMenuItemAtPath: @[E, @1] forWindow: wid];
  PASS(view->copyCount == 1, "copy: reaches the first responder");
  [client activateMenuItemAtPath: @[E, @2] forWindow: wid];
  PASS(delegate->delegateCount == 1, "action reaches the window delegate");

  /* Menu.app sends window 0 for the application-level menu. */
  [client activateMenuItemAtPath: @[E, @0] forWindow: @0];
  PASS(view->customCount == 2, "application menu action reaches the first responder");

  /* A shortcut changes what validateMenuItem: reports; Menu.app must get
     the new state without the window losing and regaining key. */
  FRServer *server = [FRServer new];
  [client setValue: server forKey: @"menuServerProxy"];
  [[NSNotificationCenter defaultCenter]
    addObserver: client
       selector: @selector(menuDidSendAction:)
           name: NSMenuDidSendActionNotification
         object: nil];
  NSEvent *key = [NSEvent keyEventWithType: NSKeyDown
                                  location: NSZeroPoint
                             modifierFlags: NSCommandKeyMask
                                 timestamp: 0
                              windowNumber: [win windowNumber]
                                   context: nil
                                characters: @"2"
               charactersIgnoringModifiers: @"2"
                                 isARepeat: NO
                                   keyCode: 0];
  PASS([main performKeyEquivalent: key], "shortcut matches the menu item");
  spin();
  PASS(view->mode, "shortcut reached the first responder");
  NSDictionary *pushed = [[[server->lastStates objectForKey: @"items"]
                            objectAtIndex: e] objectForKey: @"submenu"];
  PASS([[[[pushed objectForKey: @"items"] objectAtIndex: 4]
          objectForKey: @"state"] integerValue] == NSOnState,
       "new state of the item is pushed to Menu.app");

  /* The same item chosen in Menu.app: the state must follow there too. */
  ASSIGN(server->lastStates, nil);
  [client activateMenuItemAtPath: @[E, @4] forWindow: wid];
  spin();
  PASS(!view->mode, "item chosen in Menu.app reached the first responder");
  pushed = [[[server->lastStates objectForKey: @"items"]
              objectAtIndex: e] objectForKey: @"submenu"];
  PASS(pushed != nil
       && [[[[pushed objectForKey: @"items"] objectAtIndex: 4]
              objectForKey: @"state"] integerValue] == NSOffState,
       "new state of an item chosen in Menu.app is pushed to Menu.app");
  [client setValue: nil forKey: @"menuServerProxy"];

  /* Clicking Menu.app may take the key window away from the app; the main
     window still holds the responder chain AppKit falls back to. */
  [win resignKeyWindow];
  spin();
  PASS([NSApp keyWindow] != win, "window resigned key");
  PASS([NSApp mainWindow] == win, "window is still main");
  data = [client _serializeMenu: main];
  PASS(enabledIn(data, e, 0), "first responder action stays enabled via the main window");
  [client activateMenuItemAtPath: @[E, @0] forWindow: wid];
  PASS(view->customCount == 3, "action reaches the main window's first responder");

  [pool release];
  return 0;
}
