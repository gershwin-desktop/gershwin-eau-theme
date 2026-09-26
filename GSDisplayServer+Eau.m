/* GSDisplayServer+Eau.m - Fix popup menu window type
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
 * _NET_WM_WINDOW_TYPE property after the original method runs.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#include <stdlib.h>
#include <string.h>

static BOOL EAUIsDialogLikeWindow(NSWindow *window, int level)
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

static BOOL EAUIsMenuPanelWindow(NSWindow *window)
{
  Class menuPanelClass = NSClassFromString(@"NSMenuPanel");
  return (menuPanelClass != Nil && [window isKindOfClass: menuPanelClass]);
}

static BOOL EAUIsModalDialogWindow(NSWindow *window, int level)
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

static void EAUEnsureWindowStates(Display *dpy,
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
 * The window manager hangs a sheet from its parent's titlebar, moves it
 * with the parent and slides it in and out, but only for windows whose
 * ICCCM WM_WINDOW_ROLE is "sheet": WM_TRANSIENT_FOR, all that libs-gui sets
 * for a sheet, is also set for child windows and drawers.  The role must be
 * on the window before it is mapped, and a deferred sheet has no X window
 * before it is first ordered in, so it is set on every order-in.
 */
static NSString *EAUAttachedRoleOfWindow(NSWindow *window)
{
  if ([[window parentWindow] attachedSheet] == window)
    {
      return @"sheet";
    }
  return nil;
}

/* Only a role this theme set is removed; any other belongs to the app. */
static BOOL EAUIsAttachedRole(Display *dpy, Window xwin, Atom roleAtom)
{
  Atom actualType = None;
  int actualFormat = 0;
  unsigned long nitems = 0;
  unsigned long bytesAfter = 0;
  unsigned char *value = NULL;
  BOOL ours = NO;

  if (XGetWindowProperty(dpy, xwin, roleAtom, 0, 16, False, XA_STRING,
                         &actualType, &actualFormat, &nitems, &bytesAfter,
                         &value) == Success
      && actualType == XA_STRING && value != NULL)
    {
      NSString *role = [[NSString alloc] initWithBytes: value
                                                length: strnlen((char *)value, nitems)
                                              encoding: NSISOLatin1StringEncoding];
      ours = [role isEqualToString: @"sheet"];
    }
  if (value != NULL)
    {
      XFree(value);
    }
  return ours;
}

static void EAUMarkAttachedWindow(GSDisplayServer *server, int win)
{
  static Atom roleAtom = None;
  NSWindow *window = GSWindowWithNumber(win);
  Display *dpy = (Display *)[server serverDevice];
  Window xwin = (Window)(uintptr_t)[server windowDevice: win];
  NSString *role;

  if (window == nil || dpy == NULL || xwin == 0)
    {
      return;
    }
  if (roleAtom == None)
    {
      roleAtom = XInternAtom(dpy, "WM_WINDOW_ROLE", False);
    }

  role = EAUAttachedRoleOfWindow(window);
  if (role != nil)
    {
      const char *value = [role UTF8String];

      XChangeProperty(dpy, xwin, roleAtom, XA_STRING, 8, PropModeReplace,
                      (const unsigned char *)value, (int)strlen(value));
    }
  else if (EAUIsAttachedRole(dpy, xwin, roleAtom))
    {
      /* The same panel may later be run as an ordinary dialog. */
      XDeleteProperty(dpy, xwin, roleAtom);
    }
}

static void EAUSwizzle(Class serverClass, Class category, SEL origSel, SEL swizSel)
{
  Method origMethod = class_getInstanceMethod(serverClass, origSel);
  Method swizMethod = class_getInstanceMethod(category, swizSel);
  if (!origMethod || !swizMethod)
    return;

  /* Add our method to XGServer, then exchange implementations */
  class_addMethod(serverClass, swizSel,
                  method_getImplementation(swizMethod),
                  method_getTypeEncoding(swizMethod));
  Method addedMethod = class_getInstanceMethod(serverClass, swizSel);
  method_exchangeImplementations(origMethod, addedMethod);
}

@implementation GSDisplayServer (EauPopupMenuFix)

+ (void) load
{
  Class cls = NSClassFromString(@"XGServer");
  if (!cls)
    return;

  EAUSwizzle(cls, self, @selector(setwindowlevel::), @selector(eau_setwindowlevel::));
  EAUSwizzle(cls, self, @selector(orderwindow:::), @selector(eau_orderwindow:::));
}

- (void) eau_orderwindow: (int)op : (int)otherWin : (int)winNum
{
  if (op != NSWindowOut)
    {
      EAUMarkAttachedWindow(self, winNum);
    }
  /* Call original (swizzled) */
  [self eau_orderwindow: op : otherWin : winNum];
}

- (void) eau_setwindowlevel: (int)level : (int)win
{
  NSWindow *nswin;

  /* Call original (swizzled) */
  [self eau_setwindowlevel: level : win];

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

  if (EAUIsDialogLikeWindow(nswin, level) && EAUIsMenuPanelWindow(nswin) == NO)
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
          if (EAUIsModalDialogWindow(nswin, level) && modal != None)
            {
              states[stateCount] = modal;
              stateCount++;
            }

          EAUEnsureWindowStates(dpy, xwin, states, stateCount);
        }
    }
}

@end
