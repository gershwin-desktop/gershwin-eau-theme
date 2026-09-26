/* GBMenuClient.h - this app's side of the Menu.app global menu bar
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

@protocol GSGNUstepMenuClient <NSObject>
- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId;
// Async push: Menu.app asks the client to send its current menu.
- (oneway void)requestMenuUpdateForWindow:(NSNumber *)windowId;
// Sync pull: Menu.app asks for fresh enabled/state data right before a submenu opens.
- (bycopy id)validateMenuStateForWindow:(NSNumber *)windowId;
// Async push: Menu.app asks the client to send its application-level menu.
- (oneway void)requestApplicationMenuUpdate;
@end

@protocol GSGNUstepMenuServer <NSObject>
- (oneway void)updateMenuForWindow:(bycopy NSNumber *)windowId
                          menuData:(bycopy NSDictionary *)menuData
                        clientName:(bycopy NSString *)clientName;
- (oneway void)unregisterWindow:(bycopy NSNumber *)windowId
                     clientName:(bycopy NSString *)clientName;
// Lightweight: patches only enabled/state on the existing NSMenu without rebuilding.
- (oneway void)updateMenuEnabledStatesForWindow:(bycopy NSNumber *)windowId
                                       menuData:(bycopy NSDictionary *)menuData
                                     clientName:(bycopy NSString *)clientName;
// Application-level (frontmost-app) menu, keyed by clientName, not window.
- (oneway void)updateMenuForApplication:(bycopy NSDictionary *)menuData
                             clientName:(bycopy NSString *)clientName;
- (oneway void)unregisterApplication:(bycopy NSString *)clientName;
- (oneway void)updateApplicationMenuEnabledStates:(bycopy NSDictionary *)menuData
                                       clientName:(bycopy NSString *)clientName;
@end

/* Registers this app as MenuClient.<pid> over Distributed Objects, connects
 * to org.gnustep.Gershwin.MenuServer and keeps Menu.app's copy of the menus
 * in sync.  It used to live on the Eau theme object; as a singleton it works
 * under any theme.  Started when the bundle finishes loading, which is inside
 * -[NSApplication _init] (before the theme loads and before any main menu
 * exists), so it sees every later menu change. */
@interface GBMenuClient : NSObject <GSGNUstepMenuClient>
{
  NSMutableDictionary *menuByWindowId;
  NSString *menuClientName;
  NSConnection *menuClientConnection;
  NSPort *menuClientReceivePort;
  NSConnection *menuServerConnection;
  id menuServerProxy;
  BOOL menuServerAvailable;
  BOOL menuServerConnected;
  NSTimer *menuClientVerifyTimer;
}

+ (GBMenuClient *)sharedClient;

/* YES when Menu.app shows the menu bar (or the environment forces external
 * menus), so the in-app menu bar for the main menu must stay hidden. */
- (BOOL)hidesInAppMenuBarForMenu:(NSMenu *)menu;

/* Called for -[GSTheme setMenu:forWindow:]: hands the menu to Menu.app, or
 * installs the standard in-window menu when Menu.app cannot take it. */
- (void)setMenu:(NSMenu *)m forWindow:(NSWindow *)w;

@end
