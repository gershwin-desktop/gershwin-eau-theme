/* abinput - the few xdotool commands the A/B harness needs
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 *   abinput mousemove X Y click 1 key Tab ...
 *   abinput waitwm SECONDS
 *
 * Moves the pointer with XWarpPointer because XTest motion is a no-op on
 * Xvfb (clicks then land at the old position and button tracking waits
 * forever for the release); buttons and keys go through XTest, loaded at
 * run time so building needs no libXtst development package.  waitwm exits
 * 0 once a window manager has announced itself on the root window
 * (_NET_SUPPORTING_WM_CHECK, EWMH), or 3 after SECONDS without one. */

#include <X11/Xlib.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*FakeButtonFn)(Display *, unsigned int, Bool, unsigned long);
typedef int (*FakeKeyFn)(Display *, unsigned int, Bool, unsigned long);

int main(int argc, char **argv)
{
  Display *d = XOpenDisplay(NULL);
  if (d == NULL)
    return 1;
  Window root = DefaultRootWindow(d);

  if (argc == 3 && strcmp(argv[1], "waitwm") == 0) {
    Atom check = XInternAtom(d, "_NET_SUPPORTING_WM_CHECK", False);
    for (int tries = atoi(argv[2]) * 10; tries >= 0; tries--) {
      Atom type;
      int format;
      unsigned long count, after;
      unsigned char *data = NULL;
      if (XGetWindowProperty(d, root, check, 0, 1, False, AnyPropertyType, &type, &format,
                             &count, &after, &data) == Success && data != NULL) {
        XFree(data);
        if (count > 0) {
          XCloseDisplay(d);
          return 0;
        }
      }
      usleep(100000);
    }
    XCloseDisplay(d);
    return 3;
  }

  void *xtst = dlopen("libXtst.so.6", RTLD_NOW);
  if (xtst == NULL)
    xtst = dlopen("libXtst.so", RTLD_NOW);
  if (xtst == NULL) {
    fprintf(stderr, "abinput: libXtst not found\n");
    return 1;
  }
  FakeButtonFn fakeButton = (FakeButtonFn)dlsym(xtst, "XTestFakeButtonEvent");
  FakeKeyFn fakeKey = (FakeKeyFn)dlsym(xtst, "XTestFakeKeyEvent");
  if (fakeButton == NULL || fakeKey == NULL)
    return 1;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "mousemove") == 0 && i + 2 < argc) {
      XWarpPointer(d, None, root, 0, 0, 0, 0, atoi(argv[i + 1]), atoi(argv[i + 2]));
      XSync(d, False);
      usleep(50000);
      i += 2;
    }
    else if (strcmp(argv[i], "key") == 0 && i + 1 < argc) {
      KeyCode k = XKeysymToKeycode(d, XStringToKeysym(argv[++i]));
      fakeKey(d, k, True, 0);
      XSync(d, False);
      usleep(30000);
      fakeKey(d, k, False, 0);
      XSync(d, False);
    }
    else if (strcmp(argv[i], "click") == 0 && i + 1 < argc) {
      unsigned int button = (unsigned int)atoi(argv[++i]);
      fakeButton(d, button, True, 0);
      XSync(d, False);
      usleep(50000);
      fakeButton(d, button, False, 0);
      XSync(d, False);
    }
  }
  XCloseDisplay(d);
  return 0;
}
