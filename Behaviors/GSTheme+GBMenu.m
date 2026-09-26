/* GSTheme+GBMenu.m - route the theme's menu-bar hooks through Menu.app
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>

#import "GBMenuClient.h"

/* libs-gui asks the active theme where a window's menu goes
 * (-setMenu:forWindow:) and whether the main menu's in-app bar is shown
 * (-modifyRect:forMenu:isHorizontal:, -proposedVisibility:forMenu:).  The
 * Menu.app split is not a look, so it is swizzled onto the GSTheme base
 * implementations here and holds under any theme that does not override
 * these methods without calling super.
 *
 * -setMenu:forWindow: reaches the original only when Menu.app cannot take
 * the menu (GBMenuClient -_setStandardMenu:forWindow:); the other two fall
 * through to the original whenever the bar is not hidden. */
@implementation GSTheme (GBMenu)

- (void)gb_setMenu:(NSMenu *)m forWindow:(NSWindow *)w
{
  [[GBMenuClient sharedClient] setMenu: m forWindow: w];
}

- (NSRect)gb_modifyRect:(NSRect)rect forMenu:(NSMenu *)menu isHorizontal:(BOOL)horizontal
{
  if ([[GBMenuClient sharedClient] hidesInAppMenuBarForMenu: menu])
    {
      NSDebugLog(@"GBMenuClient: Modifying menu rect for GNUstep IPC: hiding menu bar");
      return NSZeroRect;
    }
  return [self gb_modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)gb_proposedVisibility:(BOOL)visibility forMenu:(NSMenu *)menu
{
  if ([[GBMenuClient sharedClient] hidesInAppMenuBarForMenu: menu])
    {
      NSDebugLog(@"GBMenuClient: Proposing menu visibility NO for GNUstep IPC");
      return NO;
    }
  return [self gb_proposedVisibility: visibility forMenu: menu];
}

static void GBExchange(Class cls, SEL original, SEL replacement)
{
  Method o = class_getInstanceMethod(cls, original);
  Method r = class_getInstanceMethod(cls, replacement);
  if (o == NULL || r == NULL)
    {
      NSWarnLog(@"GSTheme+GBMenu: cannot swizzle -%s", sel_getName(original));
      return;
    }
  method_exchangeImplementations(o, r);
}

+ (void)load
{
  Class cls = [GSTheme class];
  GBExchange(cls, @selector(setMenu:forWindow:), @selector(gb_setMenu:forWindow:));
  GBExchange(cls, @selector(modifyRect:forMenu:isHorizontal:),
             @selector(gb_modifyRect:forMenu:isHorizontal:));
  GBExchange(cls, @selector(proposedVisibility:forMenu:),
             @selector(gb_proposedVisibility:forMenu:));
}

@end
