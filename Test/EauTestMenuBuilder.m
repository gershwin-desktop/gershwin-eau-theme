/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauTestMenuBuilder.h"

static id<NSMenuItem> addItem(NSMenu *menu, NSString *title, SEL action, NSString *key)
{
  return [menu addItemWithTitle: title action: action keyEquivalent: key];
}

static NSMenu *addSubmenu(NSMenu *mainMenu, NSString *title)
{
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: title
                                                action: NULL
                                         keyEquivalent: @""];
  NSMenu *submenu = [[NSMenu alloc] initWithTitle: title];
  [item setSubmenu: submenu];
  [mainMenu addItem: item];
  return submenu;
}

@implementation EauTestMenuBuilder

+ (NSMenu *)mainMenuForApplicationName:(NSString *)appName
{
  NSMenu *mainMenu = [[NSMenu alloc] initWithTitle: appName];

  NSMenu *appMenu = addSubmenu(mainMenu, appName);
  addItem(appMenu, [NSString stringWithFormat: @"About %@", appName],
          @selector(orderFrontStandardAboutPanel:), @"");
  [appMenu addItem: [NSMenuItem separatorItem]];
  NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle: @"Services"];
  [addItem(appMenu, @"Services", NULL, @"") setSubmenu: servicesMenu];
  [NSApp setServicesMenu: servicesMenu];
  [appMenu addItem: [NSMenuItem separatorItem]];
  addItem(appMenu, [NSString stringWithFormat: @"Hide %@", appName],
          @selector(hide:), @"h");
  addItem(appMenu, @"Hide Others", @selector(hideOtherApplications:), @"");
  addItem(appMenu, @"Show All", @selector(unhideAllApplications:), @"");
  [appMenu addItem: [NSMenuItem separatorItem]];
  addItem(appMenu, [NSString stringWithFormat: @"Quit %@", appName],
          @selector(terminate:), @"q");

  NSMenu *fileMenu = addSubmenu(mainMenu, @"File");
  addItem(fileMenu, @"New", @selector(newDocument:), @"n");
  addItem(fileMenu, @"Open...", @selector(openDocument:), @"o");
  [fileMenu addItem: [NSMenuItem separatorItem]];
  addItem(fileMenu, @"Close", @selector(performClose:), @"w");
  addItem(fileMenu, @"Save", @selector(saveDocument:), @"s");
  addItem(fileMenu, @"Save As...", @selector(saveDocumentAs:), @"S");
  [fileMenu addItem: [NSMenuItem separatorItem]];
  addItem(fileMenu, @"Page Setup...", @selector(runPageLayout:), @"P");
  addItem(fileMenu, @"Print...", @selector(print:), @"p");

  NSMenu *editMenu = addSubmenu(mainMenu, @"Edit");
  addItem(editMenu, @"Undo", @selector(undo:), @"z");
  addItem(editMenu, @"Redo", @selector(redo:), @"Z");
  [editMenu addItem: [NSMenuItem separatorItem]];
  addItem(editMenu, @"Cut", @selector(cut:), @"x");
  addItem(editMenu, @"Copy", @selector(copy:), @"c");
  addItem(editMenu, @"Paste", @selector(paste:), @"v");
  addItem(editMenu, @"Delete", @selector(delete:), @"");
  addItem(editMenu, @"Select All", @selector(selectAll:), @"a");

  NSMenu *formatMenu = addSubmenu(mainMenu, @"Format");
  addItem(formatMenu, @"Show Fonts", @selector(orderFrontFontPanel:), @"t");
  addItem(formatMenu, @"Show Colors", @selector(orderFrontColorPanel:), @"C");

  NSMenu *windowMenu = addSubmenu(mainMenu, @"Window");
  addItem(windowMenu, @"Minimize", @selector(performMiniaturize:), @"m");
  addItem(windowMenu, @"Zoom", @selector(performZoom:), @"");
  [windowMenu addItem: [NSMenuItem separatorItem]];
  /* The showcase is a second, additional window - the uitest scripts under
   * Tests/ target the classic window this app has always opened at launch,
   * so that behavior is untouched; this is purely an extra way in. */
  addItem(windowMenu, @"Showcase", @selector(showShowcase:), @"");
  [windowMenu addItem: [NSMenuItem separatorItem]];
  addItem(windowMenu, @"Bring All to Front", @selector(arrangeInFront:), @"");
  [NSApp setWindowsMenu: windowMenu];

  NSMenu *helpMenu = addSubmenu(mainMenu, @"Help");
  addItem(helpMenu, [NSString stringWithFormat: @"%@ Help", appName],
          @selector(showHelp:), @"?");

  return mainMenu;
}

@end
