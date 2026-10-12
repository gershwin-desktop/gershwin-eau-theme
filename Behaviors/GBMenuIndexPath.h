/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef GBMenuIndexPath_h
#define GBMenuIndexPath_h

#import <AppKit/AppKit.h>

/* The item that an index path (as sent by Menu.app) names below menu, or nil.
   Every menu on the way is updated first so that apps which fill their
   submenus lazily in the delegate's -menuNeedsUpdate: (Emacs does) have
   items to resolve against. */
NSMenuItem *GBMenuItemForIndexPath(NSMenu *menu, NSArray *indexPath);

#endif
