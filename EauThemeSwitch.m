/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

#import "Eau.h"
#import "EauGrowBoxView.h"
#import "GSStandardDecorationView+Eau.h"

/* GSTheme installs the -_override<Class>Method_<selector> methods of a theme
 * subclass when the theme activates and puts the previous implementation back
 * when it deactivates - but it reads "the previous implementation" while
 * building the theme instance.  GSTheme builds a fresh instance on every
 * switch, so an instance built while Eau is already active records Eau's own
 * implementations as the ones to restore, and from then on the overrides can
 * never be taken out again: the next theme would keep drawing with Eau's
 * cells.  Remembering the untouched implementations once, before any theme
 * has run, lets -[Eau deactivate] restore what really was there. */
typedef struct
{
  Class cls;
  SEL sel;
  IMP original;
} EauOriginalMethod;

static EauOriginalMethod *gEauOriginalMethods = NULL;
static unsigned gEauOriginalMethodCount = 0;

void EauRecordOriginalOverriddenMethods(void)
{
  unsigned int count = 0;
  unsigned int i;
  Method *methods;

  if (gEauOriginalMethods != NULL)
    {
      return;
    }

  methods = class_copyMethodList([Eau class], &count);
  if (methods == NULL)
    {
      return;
    }

  gEauOriginalMethods = calloc(count, sizeof(EauOriginalMethod));
  if (gEauOriginalMethods == NULL)
    {
      free(methods);
      return;
    }

  for (i = 0; i < count; i++)
    {
      const char *name = sel_getName(method_getName(methods[i]));
      const char *tail = strstr(name, "Method_");
      char className[256];
      size_t classLength;
      Class cls;
      SEL sel;
      IMP original;

      if (strncmp(name, "_override", 9) != 0 || tail == NULL || tail <= name)
        {
          continue;
        }

      classLength = (size_t)(tail - name) - 9;
      if (classLength == 0 || classLength >= sizeof(className))
        {
          continue;
        }
      memcpy(className, name + 9, classLength);
      className[classLength] = '\0';

      cls = objc_lookUpClass(className);
      sel = sel_getUid(tail + 7);
      if (cls == 0 || sel == 0 || ![cls instancesRespondToSelector: sel])
        {
          continue;
        }

      /* Read before GSTheme has installed anything: -[Eau initWithBundle:]
       * calls this ahead of [super initWithBundle:], and that is where GSTheme
       * first patches these classes.  Nothing is added to the class here -
       * GSTheme's own class_addMethod gives the class its own method, and
       * restoring through that one cannot reach the superclass that every
       * other control shares. */
      original = [cls instanceMethodForSelector: sel];

      gEauOriginalMethods[gEauOriginalMethodCount].cls = cls;
      gEauOriginalMethods[gEauOriginalMethodCount].sel = sel;
      gEauOriginalMethods[gEauOriginalMethodCount].original = original;
      gEauOriginalMethodCount++;
    }

  free(methods);
}

void EauRestoreOverriddenMethods(void)
{
  unsigned i;

  for (i = 0; i < gEauOriginalMethodCount; i++)
    {
      Class cls = gEauOriginalMethods[i].cls;
      SEL sel = gEauOriginalMethods[i].sel;
      Method m = class_getInstanceMethod(cls, sel);

      if (m == NULL)
        {
          continue;
        }
      /* Only the method the class owns may be touched.  For a selector the
       * class merely inherits, GSTheme's class_addMethod has given it one of
       * its own; if it has not, this is the superclass' method and writing to
       * it would change every other class below it. */
      if (!class_respondsToSelector(cls, sel)
          || m == class_getInstanceMethod(class_getSuperclass(cls), sel))
        {
          continue;
        }
      if (method_getImplementation(m) != gEauOriginalMethods[i].original)
        {
          method_setImplementation(m, gEauOriginalMethods[i].original);
        }
    }
}

@interface NSProgressIndicator (EauThemeSwitch)
- (void) eau_syncProgressView;
@end

/* Once the Eau bundle has been loaded its code stays in the process for good,
 * so the pieces of the interface Eau installs into live objects - the title
 * bar buttons a window was handed when it opened, the resize grip parked in
 * the content view - have to be put back when another theme takes over, and
 * put in place again when Eau comes back.  GSTheme itself only redisplays on
 * a switch; it never rebuilds those.
 *
 * This runs for every theme activation, whichever theme it is, which is what
 * makes switching back and forth any number of times end in the same state as
 * starting out in the theme switched to. */
@interface EauThemeSwitchWatcher : NSObject
@end

@implementation EauThemeSwitchWatcher

+ (void) load
{
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(themeDidActivate:)
                                               name: GSThemeDidActivateNotification
                                             object: nil];
}

+ (void) themeDidActivate: (NSNotification *)notification
{
  NSApplication *app = NSApp;

  if (app == nil)
    {
      return;
    }

  /* The window list can change while windows are being redisplayed. */
  NSArray *windows = [[app windows] copy];
  NSEnumerator *enumerator = [windows objectEnumerator];
  NSWindow *window;

  while ((window = [enumerator nextObject]) != nil)
    {
      [self updateWindow: window];
    }

  /* An application whose menu bar Eau keeps off the screen has no window to
   * find its menu views through. */
  [self remeasureMenuView: [[app mainMenu] menuRepresentation] depth: 0];

  /* Marking views for display is not enough here.  Other observers of this
   * same notification re-measure their contents afterwards - NSMenuView
   * resizes its item cells, and Eau pads menu items, so every item in a menu
   * bar moves - and a relayout only invalidates the items themselves, leaving
   * the titles of the previous layout standing in the background.  Redrawing
   * everything once the whole notification has been delivered clears that. */
  [NSObject cancelPreviousPerformRequestsWithTarget: self
                                           selector: @selector(redisplayAllWindows)
                                             object: nil];
  [self performSelector: @selector(redisplayAllWindows)
             withObject: nil
             afterDelay: 0.0
                inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                  NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode, nil]];
}

+ (void) redisplayAllWindows
{
  NSArray *windows = [[NSApp windows] copy];
  NSEnumerator *enumerator = [windows objectEnumerator];
  NSWindow *window;

  while ((window = [enumerator nextObject]) != nil)
    {
      if ([window isVisible])
        {
          [window display];
        }
    }
}

+ (void) updateWindow: (NSWindow *)window
{
  NSView *frameView = [[window contentView] superview];

  if ([frameView isKindOfClass: [GSStandardWindowDecorationView class]])
    {
      [(GSStandardWindowDecorationView *)frameView EAUrebuildTitleBarButtons];
    }

  if (EauThemeIsActive())
    {
      if ([window isVisible])
        {
          [EauGrowBoxView addToWindow: window];
        }
    }
  else
    {
      [EauGrowBoxView removeFromWindow: window];
      EauRemoveFocusOverlayFromWindow(window);
    }

  [self updateViewTree: frameView];

  [frameView setNeedsDisplay: YES];
  [[window contentView] setNeedsDisplay: YES];
}

/* Controls that Eau renders through a view of its own have to be told, since
 * nothing else in the application will touch them until their value changes. */
+ (void) updateViewTree: (NSView *)view
{
  NSEnumerator *enumerator;
  NSView *subview;

  if (view == nil)
    {
      return;
    }

  if ([view isKindOfClass: [NSProgressIndicator class]])
    {
      [(NSProgressIndicator *)view eau_syncProgressView];
      return;
    }

  if ([view isKindOfClass: [NSMenuView class]])
    {
      [self remeasureMenuView: (NSMenuView *)view depth: 0];
    }

  enumerator = [[[view subviews] copy] objectEnumerator];
  while ((subview = [enumerator nextObject]) != nil)
    {
      [self updateViewTree: subview];
    }
}

/* Menu item cells keep the widths they measured with, and every theme
 * measures them differently - Eau pads the title and spells key equivalents
 * with the Mac symbols.  NSMenuView only drops those measurements for the
 * menu representation NSMenu itself owns, so a menu bar held by a view of its
 * own (Menu.app's) would keep drawing items at the sizes of the theme that
 * has just gone, clipping key equivalents and submenu arrows off their
 * right-hand edge. */
+ (void) remeasureMenuView: (NSMenuView *)menuView depth: (NSInteger)depth
{
  NSMenu *menu;
  NSInteger count;
  NSInteger i;

  /* Menus nest, but not that deeply; the limit is only there so a menu that
   * somehow refers back to itself cannot run this off the stack. */
  if (menuView == nil || depth > 16)
    {
      return;
    }

  menu = [menuView menu];
  count = (menu != nil) ? [menu numberOfItems] : 0;

  for (i = 0; i < count; i++)
    {
      NSMenu *submenu = [[menu itemAtIndex: i] submenu];

      [[menuView menuItemCellForItemAtIndex: i] setNeedsSizing: YES];
      if (submenu != nil && [submenu menuRepresentation] != menuView)
        {
          [self remeasureMenuView: [submenu menuRepresentation] depth: depth + 1];
        }
    }
  [menuView setNeedsSizing: YES];
  [menuView sizeToFit];
  [menuView setNeedsDisplay: YES];
}

@end
