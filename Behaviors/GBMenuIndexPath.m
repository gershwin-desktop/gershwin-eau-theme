/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBMenuIndexPath.h"

NSMenuItem *GBMenuItemForIndexPath(NSMenu *menu, NSArray *indexPath)
{
  if (menu == nil || [indexPath count] == 0)
    {
      return nil;
    }

  NSMenu *currentMenu = menu;
  NSMenuItem *currentItem = nil;

  for (NSUInteger i = 0; i < [indexPath count]; i++)
    {
      /* Such apps empty their submenus whenever they rebuild the top level,
         and the sent path was taken from a fuller state. */
      [currentMenu update];

      NSInteger index = [[indexPath objectAtIndex:i] integerValue];
      if (index < 0 || index >= [currentMenu numberOfItems])
        {
          return nil;
        }

      currentItem = [currentMenu itemAtIndex:index];
      if (i < [indexPath count] - 1)
        {
          if (![currentItem hasSubmenu])
            {
              return nil;
            }
          currentMenu = [currentItem submenu];
        }
    }

  return currentItem;
}
