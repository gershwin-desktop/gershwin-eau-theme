/* GSDisplayServer+GB.m - Fix popup menu window type
   Copyright (C) 2026 Free Software Foundation, Inc.

   This file is part of GNUstep.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; see the file COPYING.LIB.
   If not, see <http://www.gnu.org/licenses/> or write to the
   Free Software Foundation, 51 Franklin Street, Fifth Floor,
   Boston, MA 02110-1301, USA.
*/

/*
 * libs-back sets _NET_WM_WINDOW_TYPE_DIALOG instead of
 * _NET_WM_WINDOW_TYPE_POPUP_MENU for NSPopUpMenuWindowLevel windows
 * (XGServerWindow.m:3479). This causes the window manager to decorate
 * popup menus with frames/titlebars instead of mapping them undecorated.
 *
 * This category swizzles -setwindowlevel:: on XGServer to fix the
 * _NET_WM_WINDOW_TYPE property after the original method runs.  It lives in
 * GershwinBehaviors rather than a theme because every theme needs it.
 *
 * TODO: Upstream to GNUstep - libs-back XGServerWindow -setwindowlevel::
 * should set _NET_WM_WINDOW_TYPE_POPUP_MENU for NSPopUpMenuWindowLevel.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#include <stdlib.h>
#include <string.h>

#import "GBSheet.h"
#import "GBTheme.h"
#import "GBThemeHooks+WindowRole.h"
#import "GBX11WindowRole.h"

static BOOL GBIsDialogLikeWindow(NSWindow *window, int level)
{
  if (window == nil)
    {
      return NO;
    }

  if ([window isKindOfClass: [NSPanel class]])
    {
      return YES;
    }

  if (level >= NSModalPanelWindowLevel)
    {
      return YES;
    }

  if (([window styleMask] & NSUtilityWindowMask) != 0)
    {
      return YES;
    }

  return NO;
}

static BOOL GBIsMenuPanelWindow(NSWindow *window)
{
  Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
  return (menuPanelClass != Nil && [window isKindOfClass: menuPanelClass]);
}

static BOOL GBIsModalDialogWindow(NSWindow *window, int level)
{
  if (window == nil)
    {
      return NO;
    }

  if (level >= NSModalPanelWindowLevel)
    {
      return YES;
    }

  return NO;
}

static void GBEnsureWindowStates(Display *dpy,
                                  Window xwin,
                                  Atom *requiredStates,
                                  unsigned int requiredCount)
{
  Atom wmState;
  Atom actualType = None;
  int actualFormat = 0;
  unsigned long nitems = 0;
  unsigned long bytesAfter = 0;
  unsigned char *existing = NULL;
  Atom *newStates;
  BOOL changed = NO;
  unsigned int missingCount = 0;
  unsigned long i;
  unsigned int r;
  unsigned long outIndex;

  wmState = XInternAtom(dpy, "_NET_WM_STATE", False);
  if (wmState == None || requiredStates == NULL || requiredCount == 0)
    {
      return;
    }

  if (XGetWindowProperty(dpy,
                         xwin,
                         wmState,
                         0,
                         1024,
                         False,
                         XA_ATOM,
                         &actualType,
                         &actualFormat,
                         &nitems,
                         &bytesAfter,
                         &existing) == Success
      && actualType == XA_ATOM
      && actualFormat == 32)
    {
      Atom *states = (Atom *)existing;
      for (r = 0; r < requiredCount; r++)
        {
          BOOL found = NO;
          for (i = 0; i < nitems; i++)
            {
              if (states[i] == requiredStates[r])
                {
                  found = YES;
                  break;
                }
            }
          if (found == NO)
            {
              missingCount++;
            }
        }

      if (missingCount > 0)
        {
          newStates = (Atom *)calloc((size_t)nitems + missingCount, sizeof(Atom));
          if (newStates != NULL)
            {
              for (i = 0; i < nitems; i++)
                {
                  newStates[i] = states[i];
                }

              outIndex = nitems;
              for (r = 0; r < requiredCount; r++)
                {
                  BOOL found = NO;
                  for (i = 0; i < nitems; i++)
                    {
                      if (states[i] == requiredStates[r])
                        {
                          found = YES;
                          break;
                        }
                    }
                  if (found == NO)
                    {
                      newStates[outIndex] = requiredStates[r];
                      outIndex++;
                    }
                }

              XChangeProperty(dpy,
                              xwin,
                              wmState,
                              XA_ATOM,
                              32,
                              PropModeReplace,
                              (unsigned char *)newStates,
                              (int)outIndex);
              free(newStates);
              changed = YES;
            }
        }
    }

  if (existing != NULL)
    {
      XFree(existing);
    }

  if (changed == NO && nitems == 0)
    {
      Atom *initialStates;
      initialStates = (Atom *)calloc(requiredCount, sizeof(Atom));
      if (initialStates == NULL)
        {
          return;
        }
      for (r = 0; r < requiredCount; r++)
        {
          initialStates[r] = requiredStates[r];
        }
      XChangeProperty(dpy,
                      xwin,
                      wmState,
                      XA_ATOM,
                      32,
                      PropModeReplace,
                      (unsigned char *)initialStates,
                      (int)requiredCount);
      free(initialStates);
    }
}

/*
 * The window manager attaches a sheet to its parent's titlebar and a drawer
 * to its parent's edge, moves them with the parent and slides them in and
 * out, but only for windows whose ICCCM WM_WINDOW_ROLE says "sheet" or
 * "drawer": WM_TRANSIENT_FOR, all that libs-gui sets, is also set for
 * dialogs and child windows.  The role must be on the window before it is
 * mapped, and a deferred window has no X window before it is first ordered
 * in, so it is set on every order-in.  This covers libs-gui's own sheets
 * (app-modal fallback) as well as GBSheet ones, which GBSheetX11.m also
 * marks when attaching.  A drawer is only a drawer when the theme takes
 * over its placement (libs-gui otherwise moves it from a timer and the two
 * would fight), so its role and outline come from theme hooks.  The
 * drawer's edge and offsets are not passed on: the window manager reads
 * them off where the drawer is put.
 */
static NSString *GBAttachedRoleOfWindow(NSWindow *window)
{
  id theme;

  if ([[window parentWindow] attachedSheet] == window || GBSheetIsActive(window))
    {
      return GBWindowRoleSheet;
    }
  theme = GBThemeIfResponds(@selector(windowManagerRoleForWindow:));
  if (theme != nil)
    {
      NSString *role = [theme windowManagerRoleForWindow: window];

      if ([role isEqualToString: GBWindowRoleDrawer])
        {
          return GBWindowRoleDrawer;
        }
    }
  return nil;
}

/* The WM cuts the outline (_WM_SHAPE_PATH) with a smooth edge and bends the
 * shadow along; the theme decides the shape. */
static void GBSetShapePath(Display *dpy, Window xwin, NSWindow *window)
{
  static Atom pathAtom = None;
  id theme = GBThemeIfResponds(@selector(windowManagerShapePathForWindow:));
  NSData *path = [theme windowManagerShapePathForWindow: window];
  const int32_t *values = [path bytes];
  NSUInteger count = [path length] / sizeof(int32_t);
  long *items;
  NSUInteger i;

  if (count == 0)
    {
      return;
    }
  items = calloc(count, sizeof(long));
  if (items == NULL)
    {
      return;
    }
  if (pathAtom == None)
    {
      pathAtom = XInternAtom(dpy, "_WM_SHAPE_PATH", False);
    }
  /* Xlib passes 32-bit items as long. */
  for (i = 0; i < count; i++)
    {
      items[i] = values[i];
    }
  XChangeProperty(dpy, xwin, pathAtom, XA_INTEGER, 32, PropModeReplace,
                  (unsigned char *)items, (int)count);
  free(items);
}

static void GBMarkAttachedWindow(GSDisplayServer *server, int win)
{
  NSWindow *window = GSWindowWithNumber(win);
  Display *dpy = (Display *)[server serverDevice];
  Window xwin = (Window)(uintptr_t)[server windowDevice: win];
  NSString *role;

  if (window == nil || dpy == NULL || xwin == 0)
    {
      return;
    }

  role = GBAttachedRoleOfWindow(window);
  if (role != nil)
    {
      GBX11SetAttachedRole(dpy, xwin, role);
      if (role == GBWindowRoleDrawer)
        {
          GBSetShapePath(dpy, xwin, window);
        }
    }
  else
    {
      /* The same panel may later be run as an ordinary dialog. */
      GBX11ClearAttachedRole(dpy, xwin);
    }
}

static void GBSwizzle(Class serverClass, Class category, SEL origSel, SEL swizSel)
{
  Method origMethod = class_getInstanceMethod(serverClass, origSel);
  Method swizMethod = class_getInstanceMethod(category, swizSel);
  Method addedMethod;

  if (!origMethod || !swizMethod)
    return;

  /* Add our method to XGServer, then exchange implementations */
  class_addMethod(serverClass, swizSel,
                  method_getImplementation(swizMethod),
                  method_getTypeEncoding(swizMethod));
  addedMethod = class_getInstanceMethod(serverClass, swizSel);
  method_exchangeImplementations(origMethod, addedMethod);
}

@implementation GSDisplayServer (GBPopupMenuFix)

+ (void) load
{
  Class cls = NSClassFromString(@"XGServer");
  if (!cls)
    return;

  /* No dispatch_once: +load already runs once per class. */
  GBSwizzle(cls, self, @selector(setwindowlevel::), @selector(gb_setwindowlevel::));
  GBSwizzle(cls, self, @selector(orderwindow:::), @selector(gb_orderwindow:::));
}

- (void) gb_orderwindow: (int)op : (int)otherWin : (int)winNum
{
  if (op != NSWindowOut)
    {
      GBMarkAttachedWindow(self, winNum);
    }
  /* Call original (swizzled) */
  [self gb_orderwindow: op : otherWin : winNum];
}

- (void) gb_setwindowlevel: (int)level : (int)win
{
  NSWindow *nswin;

  /* Call original (swizzled) */
  [self gb_setwindowlevel: level : win];

  nswin = GSWindowWithNumber(win);
  if (nswin == nil)
    {
      return;
    }

  /* Fix popup menu window type: libs-back sets DIALOG instead of POPUP_MENU */
  if (level == NSPopUpMenuWindowLevel)
    {
      /* Only fix actual menu panel windows. NSPopUpMenuWindowLevel is shared
         by tooltips, autocomplete, drag views, popovers, and other windows
         that must keep the default DIALOG type. */
      Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
      if (menuPanelClass != Nil && [nswin isKindOfClass: menuPanelClass])
        {
          Display *dpy = (Display *)[self serverDevice];
          Window xwin = (Window)(uintptr_t)[self windowDevice: win];
          if (dpy != NULL && xwin != 0)
            {
              Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
              Atom popupType = XInternAtom(dpy,
                                           "_NET_WM_WINDOW_TYPE_POPUP_MENU",
                                           False);
              XChangeProperty(dpy,
                              xwin,
                              wmType,
                              XA_ATOM,
                              32,
                              PropModeReplace,
                              (unsigned char *)&popupType,
                              1);
            }
        }
    }

  if (GBIsDialogLikeWindow(nswin, level) && GBIsMenuPanelWindow(nswin) == NO)
    {
      Display *dpy = (Display *)[self serverDevice];
      Window xwin = (Window)(uintptr_t)[self windowDevice: win];
      if (dpy != NULL && xwin != 0)
        {
          Atom wmType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
          Atom dialogType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DIALOG", False);
          if (wmType != None && dialogType != None)
            {
              XChangeProperty(dpy, xwin, wmType, XA_ATOM, 32,
                              PropModeReplace,
                              (unsigned char *)&dialogType, 1);
            }

          Atom skipTaskbar;
          Atom skipPager;
          Atom modal;
          Atom states[3];
          unsigned int stateCount = 0;

          skipTaskbar = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
          skipPager = XInternAtom(dpy, "_NET_WM_STATE_SKIP_PAGER", False);
          modal = XInternAtom(dpy, "_NET_WM_STATE_MODAL", False);

          if (skipTaskbar != None)
            {
              states[stateCount] = skipTaskbar;
              stateCount++;
            }
          if (skipPager != None)
            {
              states[stateCount] = skipPager;
              stateCount++;
            }
          if (GBIsModalDialogWindow(nswin, level) && modal != None)
            {
              states[stateCount] = modal;
              stateCount++;
            }

          GBEnsureWindowStates(dpy, xwin, states, stateCount);
        }
    }
}

@end
