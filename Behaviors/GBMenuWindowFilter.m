/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GBMenuWindowFilter.h"

#import <math.h>
#import <string.h>
#import <X11/Xatom.h>
#import <X11/Xutil.h>

int GBMenuUtilityHeightLimit(CGFloat menuBarHeight, CGFloat scaleFactor)
{
  /* Round up: the backend may round a fractional device height either way,
     and a utility window must never end up one pixel above the limit. */
  return (int)ceil(menuBarHeight * scaleFactor);
}

/* GNUstep gives ALL of a menu app's windows the class hint "Menu", "Menu" -
   the bar, dropdowns, panels and caches alike - so the class only tells
   Menu.app's windows apart from those of other applications. */
static BOOL isMenuAppWindow(Display *dpy, Window w)
{
  XClassHint classHint;
  if (!XGetClassHint(dpy, w, &classHint))
    return NO;
  BOOL isMenu = (classHint.res_name
                 && strcmp(classHint.res_name, "Menu") == 0
                 && classHint.res_class
                 && strcmp(classHint.res_class, "Menu") == 0);
  XFree(classHint.res_name);
  XFree(classHint.res_class);
  return isMenu;
}

static BOOL hasWindowType(Display *dpy, Window w, const char *typeName)
{
  /* Only-if-exists: an atom nobody interned yet cannot be set on any window. */
  Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", True);
  Atom wanted = XInternAtom(dpy, typeName, True);
  if (wmType == None || wanted == None)
    return NO;

  Atom actualType;
  int actualFormat;
  unsigned long nitems;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  if (XGetWindowProperty(dpy, w, wmType, 0, 32, False, XA_ATOM,
                         &actualType, &actualFormat, &nitems, &bytesAfter,
                         &data) != Success)
    return NO;

  BOOL found = NO;
  if (data != NULL)
    {
      if (actualType == XA_ATOM && actualFormat == 32)
        {
          Atom *types = (Atom *)data;
          for (unsigned long i = 0; i < nitems && !found; i++)
            found = (types[i] == wanted);
        }
      XFree(data);
    }
  return found;
}

BOOL GBIsMenuDropdownWindow(Display *dpy, Window w, int height,
                            int utilityHeightLimit)
{
  if (!isMenuAppWindow(dpy, w))
    return NO;

  /* Menu.app marks its bar as a DOCK itself.  Unlike the bar's height, that
     does not change with the scale factor.  Dropdown types cannot be used the
     other way round: libs-back only sets them when it found an EWMH window
     manager at startup, and the session starts Menu before the WM. */
  if (hasWindowType(dpy, w, "_NET_WM_WINDOW_TYPE_DOCK"))
    return NO;

  /* A dropdown is taller than a menu item, so anything up to the scaled bar
     height is one of the small utility windows. */
  return height > utilityHeightLimit;
}
