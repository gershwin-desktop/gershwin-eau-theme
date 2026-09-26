/* GBSheetX11.m - window-manager hints for window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - libs-back should mark attached sheets with
 * _NET_WM_STATE_MODAL and undecorated Motif hints when the style mask of a
 * live window changes, instead of only at window creation.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <X11/Xatom.h>
#import <X11/Xlib.h>
#include <stdlib.h>
#include <string.h>

#import "GBSheet.h"

/* The WM needs three things to treat a sheet like one: WM_TRANSIENT_FOR so
 * it stacks and moves with the parent, _NET_WM_STATE_MODAL so it knows the
 * parent is blocked, and Motif hints without decorations so it does not
 * frame the sheet.  libs-back only knows the style mask the window was
 * created with, so the hints are written here with Xlib, the same way
 * GSDisplayServer+Eau.m fixes window types.  The previous Motif hints are
 * kept so a panel reused later as a normal window gets its frame back. */

static const void *kGBSheetSavedMotifKey = &kGBSheetSavedMotifKey;

/* Layout of _MOTIF_WM_HINTS: five longs (flags, functions, decorations,
 * input mode, status); flag bit 1 says the decorations field is valid. */
#define GB_MWM_HINTS_DECORATIONS (1L << 1)
#define GB_MWM_HINTS_ELEMENTS 5

static BOOL GBSheetXWindow(NSWindow *window, Display **dpy, Window *xwin)
{
  GSDisplayServer *srv;
  Class xgServer = NSClassFromString(@"XGServer");
  int num = (int)[window windowNumber];

  if (window == nil || num == 0 || xgServer == Nil) {
    return NO;
  }
  srv = GSServerForWindow(window);
  if (srv == nil || [srv isKindOfClass:xgServer] == NO) {
    return NO;
  }
  *dpy = (Display *)[srv serverDevice];
  *xwin = (Window)(uintptr_t)[srv windowDevice:num];
  return (*dpy != NULL && *xwin != 0);
}

static void GBSheetSetModalState(Display *dpy, Window xwin, BOOL add)
{
  Atom wmState = XInternAtom(dpy, "_NET_WM_STATE", False);
  Atom modal = XInternAtom(dpy, "_NET_WM_STATE_MODAL", False);
  Atom actualType = None;
  int actualFormat = 0;
  unsigned long nitems = 0;
  unsigned long bytesAfter = 0;
  unsigned char *data = NULL;
  Atom *states;
  unsigned long i;
  unsigned long count = 0;

  if (wmState == None || modal == None) {
    return;
  }
  if (XGetWindowProperty(dpy, xwin, wmState, 0, 1024, False, XA_ATOM, &actualType, &actualFormat,
                         &nitems, &bytesAfter, &data) != Success ||
      actualType != XA_ATOM || actualFormat != 32) {
    nitems = 0;
  }

  states = (Atom *)calloc(nitems + 1, sizeof(Atom));
  if (states == NULL) {
    if (data != NULL) {
      XFree(data);
    }
    return;
  }
  for (i = 0; i < nitems; i++) {
    Atom a = ((Atom *)data)[i];
    if (a != modal) {
      states[count++] = a;
    }
  }
  if (add) {
    states[count++] = modal;
  }
  if (data != NULL) {
    XFree(data);
  }

  /* Written as a property because the sheet is not mapped yet when it is
   * attached (and already withdrawn when detached): EWMH has the WM read
   * _NET_WM_STATE at map time. */
  XChangeProperty(dpy, xwin, wmState, XA_ATOM, 32, PropModeReplace, (unsigned char *)states,
                  (int)count);
  free(states);
}

void GBSheetX11Attach(NSWindow *sheet, NSWindow *parent)
{
  Display *dpy;
  Window xsheet;
  Window xparent;
  Atom motif;
  Atom actualType = None;
  int actualFormat = 0;
  unsigned long nitems = 0;
  unsigned long bytesAfter = 0;
  unsigned char *data = NULL;
  long hints[GB_MWM_HINTS_ELEMENTS] = { GB_MWM_HINTS_DECORATIONS, 0, 0, 0, 0 };
  NSData *saved = nil;

  if (GBSheetXWindow(sheet, &dpy, &xsheet) == NO) {
    return;
  }

  motif = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
  if (motif != None) {
    if (XGetWindowProperty(dpy, xsheet, motif, 0, GB_MWM_HINTS_ELEMENTS, False, motif, &actualType,
                           &actualFormat, &nitems, &bytesAfter, &data) == Success &&
        actualType == motif && actualFormat == 32 && nitems > 0) {
      /* Format-32 properties come back as longs (Xlib quirk). */
      saved = [NSData dataWithBytes:data length:nitems * sizeof(long)];
    }
    if (data != NULL) {
      XFree(data);
    }
    objc_setAssociatedObject(sheet, kGBSheetSavedMotifKey,
                             saved != nil ? (id)saved : (id)[NSNull null],
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    XChangeProperty(dpy, xsheet, motif, motif, 32, PropModeReplace, (unsigned char *)hints,
                    GB_MWM_HINTS_ELEMENTS);
  }

  if (GBSheetXWindow(parent, &dpy, &xparent)) {
    XSetTransientForHint(dpy, xsheet, xparent);
  }
  GBSheetSetModalState(dpy, xsheet, YES);
  XFlush(dpy);
}

void GBSheetX11Detach(NSWindow *sheet)
{
  Display *dpy;
  Window xsheet;
  Atom motif;
  id saved;

  if (GBSheetXWindow(sheet, &dpy, &xsheet) == NO) {
    return;
  }

  XDeleteProperty(dpy, xsheet, XA_WM_TRANSIENT_FOR);
  GBSheetSetModalState(dpy, xsheet, NO);

  motif = XInternAtom(dpy, "_MOTIF_WM_HINTS", False);
  saved = objc_getAssociatedObject(sheet, kGBSheetSavedMotifKey);
  if (motif != None && saved != nil) {
    if ([saved isKindOfClass:[NSData class]]) {
      NSData *bytes = saved;
      XChangeProperty(dpy, xsheet, motif, motif, 32, PropModeReplace,
                      (unsigned char *)[bytes bytes], (int)([bytes length] / sizeof(long)));
    }
    else {
      XDeleteProperty(dpy, xsheet, motif);
    }
  }
  objc_setAssociatedObject(sheet, kGBSheetSavedMotifKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  XFlush(dpy);
}
