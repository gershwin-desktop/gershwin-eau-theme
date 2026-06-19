/*
   NSMenu+Eau.m

   Swizzles NSMenu methods to enable NSMacintoshInterfaceStyle support
   with upstream (unmodified) libs-gui.

   This allows the Eau theme to:
   1. Receive notifications when the main menu changes
   2. Control menu visibility (hide in-app menu bar for global menu)
   3. Detect and close orphaned dropdown menu windows that should have
      been closed when the user switched to a different top-level menu
      item but weren't due to a tracking-loop cleanup gap
*/

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>
#import <X11/Xutil.h>

#import "Eau.h"

/* ---- NSMenuPanel forward declaration (private) ---- */
@interface NSObject (EauMenuPanel)
- (id)_menu;
@end

/* ---- NSMenuPanel swizzles: clamp menu windows to screen bounds ---- */

// Shared bottom-clamp helper: if the window extends past the screen
// borders, shift it to fit entirely on screen.
// Uses the original setFrame:display: IMP to avoid recursion.
static void (*s_orig_menuWindowSetFrameDisplay)(id, SEL, NSRect, BOOL) = NULL;

static BOOL _eau_clampMenuWindowToScreenBounds(id window)
{
  NSRect frame = [window frame];
  NSScreen *screen = [window screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (!screen) return NO;

  NSRect screenFrame = [screen frame];
  BOOL needsClamp = NO;

  // Bottom edge — shift up
  if (frame.origin.y < screenFrame.origin.y)
    {
      frame.origin.y = screenFrame.origin.y;
      needsClamp = YES;
    }

  // Top edge — shift down
  if (NSMaxY(frame) > NSMaxY(screenFrame))
    {
      frame.origin.y = NSMaxY(screenFrame) - frame.size.height;
      needsClamp = YES;
    }

  // Left edge — shift right
  if (frame.origin.x < screenFrame.origin.x)
    {
      frame.origin.x = screenFrame.origin.x;
      needsClamp = YES;
    }

  // Right edge — shift left
  if (NSMaxX(frame) > NSMaxX(screenFrame))
    {
      frame.origin.x = NSMaxX(screenFrame) - frame.size.width;
      needsClamp = YES;
    }

  if (needsClamp)
    {
      // Use the original IMP directly to avoid re-entering the swizzle.
      if (s_orig_menuWindowSetFrameDisplay)
        s_orig_menuWindowSetFrameDisplay(window, @selector(setFrame:display:), frame, NO);
      return YES;
    }
  return NO;
}

static void (*s_orig_menuWindowSetFrameOrigin)(id, SEL, NSPoint) = NULL;

static void s_eau_menuWindowSetFrameOrigin(id self, SEL _cmd, NSPoint aPoint)
{
  if (s_orig_menuWindowSetFrameOrigin)
    s_orig_menuWindowSetFrameOrigin(self, _cmd, aPoint);
  _eau_clampMenuWindowToScreenBounds(self);
}

static void s_eau_menuWindowSetFrameDisplay(id self, SEL _cmd, NSRect frameRect, BOOL flag)
{
  if (s_orig_menuWindowSetFrameDisplay)
    s_orig_menuWindowSetFrameDisplay(self, _cmd, frameRect, flag);
  _eau_clampMenuWindowToScreenBounds(self);
}

static void _eau_swizzleMenuWindowFrameMethods(void)
{
  Class menuPanelClass = objc_getClass("NSMenuPanel");
  if (!menuPanelClass)
    {
      EAULOG(@"Eau: NSMenuPanel class not found, skipping menu window swizzles");
      return;
    }

  // Swizzle setFrameOrigin:
  SEL selOrigin = sel_registerName("setFrameOrigin:");
  Method mOrigin = class_getInstanceMethod(menuPanelClass, selOrigin);
  if (mOrigin)
    {
      s_orig_menuWindowSetFrameOrigin = (void (*)(id, SEL, NSPoint))method_getImplementation(mOrigin);
      method_setImplementation(mOrigin, (IMP)s_eau_menuWindowSetFrameOrigin);
      EAULOG(@"Eau: Swizzled NSMenuPanel setFrameOrigin: for bottom-screen clamping");
    }

  // Swizzle setFrame:display: (catches sizeToFit calls that bypass setFrameOrigin:)
  SEL selFrameDisplay = sel_registerName("setFrame:display:");
  Method mFrameDisplay = class_getInstanceMethod(menuPanelClass, selFrameDisplay);
  if (mFrameDisplay)
    {
      s_orig_menuWindowSetFrameDisplay = (void (*)(id, SEL, NSRect, BOOL))method_getImplementation(mFrameDisplay);
      method_setImplementation(mFrameDisplay, (IMP)s_eau_menuWindowSetFrameDisplay);
      EAULOG(@"Eau: Swizzled NSMenuPanel setFrame:display: for bottom-screen clamping");
    }
}

/* ---- Tracked windows + active tracking counter ---- */
static volatile int _eau_activeTrackingCount = 0;
static Display *_eau_x11_display = NULL;

static void _eau_ensureState(void)
{
  if (_eau_x11_display == NULL)
    _eau_x11_display = XOpenDisplay(NULL);
}

/* ---- Destroy ALL X11 "Menu" windows + their containers ---- */
static void _eau_destroyX11MenuWindows(void)
{
  _eau_ensureState();
  if (_eau_x11_display == NULL) return;

  /* Walk the X11 tree looking for GNUstep "Menu" windows in Normal
     state.  These are orphaned dropdowns.  We destroy BOTH the
     window AND its parent container, because the NSWindow's X11
     window is often a child of an unmanaged container (0x40f7ce
     style) that stays visible even after the child is destroyed. */
  Window root = DefaultRootWindow(_eau_x11_display);
  Window unused_root, unused_parent;
  Window *children = NULL;
  unsigned int nchildren = 0;

  if (!XQueryTree(_eau_x11_display, root, &unused_root, &unused_parent,
                  &children, &nchildren))
    return;

  for (unsigned int i = 0; i < nchildren; i++)
    {
      Window w = children[i];
      XWindowAttributes attr;
      if (!XGetWindowAttributes(_eau_x11_display, w, &attr))
        continue;
      if (attr.map_state != IsViewable)
        continue;

      /* Check WM_CLASS for "Menu" "GNUstep" */
      XClassHint classHint;
      if (!XGetClassHint(_eau_x11_display, w, &classHint))
        continue;
      BOOL isMenu = (classHint.res_name
                     && strcmp(classHint.res_name, "Menu") == 0
                     && classHint.res_class
                     && strcmp(classHint.res_class, "GNUstep") == 0);
      XFree(classHint.res_name);
      XFree(classHint.res_class);
      if (!isMenu)
        continue;

      /* Skip the menu bar itself — it's a "Menu" "GNUstep" window
         too but sits at y=0 with the menu bar height (~22px).
         Only destroy windows that are clearly dropdowns (>25px). */
      if (attr.y == 0 && attr.height <= 25)
        continue;

      /* Found a visible GNUstep Menu window.  Destroy the parent
         container (w itself may be the child).  Walk up one level
         to find the actual parent container to destroy. */
      Window parent = w;
      Window root2 = None;
      Window *children2 = NULL;
      unsigned int nc2 = 0;
      if (XQueryTree(_eau_x11_display, parent, &root2, &parent,
                     &children2, &nc2))
        {
          if (children2) XFree(children2);
        }
      // parent now holds the actual parent of w

      // Also recurse into children to destroy any sub-windows
      // (deeper submenus)
      Window *subchildren = NULL;
      unsigned int nsub = 0;
      if (XQueryTree(_eau_x11_display, w, &unused_root, &unused_parent,
                     &subchildren, &nsub))
        {
          for (unsigned int j = 0; j < nsub; j++)
            {
              XDestroyWindow(_eau_x11_display, subchildren[j]);
            }
          if (subchildren) XFree(subchildren);
        }

      // Destroy w itself
      XDestroyWindow(_eau_x11_display, w);

      // If parent is not root, also destroy the parent container
      if (parent != root && parent != None)
        {
          XDestroyWindow(_eau_x11_display, parent);
        }
    }

  if (children) XFree(children);
  XSync(_eau_x11_display, False);
}

/* ---- trackWithEvent: swizzle (increment/decrement, then cleanup) ---- */

/* ---- trackWithEvent: swizzle (increment/decrement, then cleanup) ---- */
static BOOL (*s_orig_trackWithEvent)(id, SEL, id) = NULL;

static BOOL s_eau_trackWithEvent(id self, SEL _cmd, NSEvent *event)
{
  _eau_activeTrackingCount++;
  BOOL result = NO;
  @try
    {
      if (s_orig_trackWithEvent)
        result = s_orig_trackWithEvent(self, _cmd, event);
    }
  @catch (NSException *e) {}
  _eau_activeTrackingCount--;
  _eau_destroyX11MenuWindows();
  return result;
}

@implementation NSMenu (Eau)

#pragma mark - Swizzled Methods

/**
 * Swizzled -menuChanged implementation.
 *
 * The original menuChanged propagates up the menu hierarchy and sets
 * _menu.mainMenuChanged when reaching the main menu. Upstream only
 * handles this flag for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when the
 * change reaches the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_menuChanged
{
  // Call original implementation (handles propagation and flag setting)
  [self eau_menuChanged];

  // If this is the main menu and using Macintosh style, post notification
  if ([NSApp mainMenu] == self)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -setMain: implementation.
 *
 * The original setMain: configures the menu as the application's main menu.
 * Upstream only calls updateAllWindowsWithMenu: for NSWindows95InterfaceStyle.
 *
 * This swizzle posts NSMacintoshMenuDidChangeNotification when a menu
 * becomes the main menu and NSMacintoshInterfaceStyle is active.
 */
- (void)eau_setMain:(BOOL)isMain
{
  // Call original implementation
  [self eau_setMain:isMain];

  // If becoming main menu and using Macintosh style, post notification
  if (isMain)
    {
      NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
      if (style == NSMacintoshInterfaceStyle)
        {
          [[NSNotificationCenter defaultCenter]
            postNotificationName:@"NSMacintoshMenuDidChangeNotification"
            object:self];
        }
    }
}

/**
 * Swizzled -display implementation.
 *
 * The original display method shows the menu window unconditionally.
 * While upstream has proposedVisibility:forMenu: in _isVisible, this
 * is only used for querying state, not controlling display.
 *
 * This swizzle checks proposedVisibility:forMenu: before displaying,
 * allowing the theme to hide the in-app menu bar when using a global
 * menu bar (Menu.app).  Additionally, before showing a new dropdown it
 * closes any orphaned menu windows from a previous tracking session
 * that were not properly cleaned up.
 */
- (void)eau_display
{
  // Let theme control visibility
  // The theme's proposedVisibility:forMenu: returns NO for the main menu
  // when Menu.app is available, hiding the in-app menu bar
  if (![[GSTheme theme] proposedVisibility:YES forMenu:self])
    {
      return;
    }

  // Call original implementation
  [self eau_display];
}

/**
 * Swizzled -displayTransient implementation.
 *
 * Pass-through for transient menus (context menus, torn-off menus, etc.).
 * Bottom-screen clamping is handled by the NSMenuPanel setFrameOrigin:
 * swizzle which catches all menu window positioning.
 */
- (void)eau_displayTransient
{
  [self eau_displayTransient];
}

/**
 * Swizzled -close implementation.
 *
 * Tracks that the menu's window is being closed.
 */
- (void)eau_close
{
  [self eau_close];
}

/**
 * Swizzled -closeTransient implementation.
 */
- (void)eau_closeTransient
{
  [self eau_closeTransient];
}

/**
 * Swizzled -_attachMenu: implementation.
 */
- (void)eau_attachMenu:(NSMenu *)aMenu
{
  [self eau_attachMenu:aMenu];
}

@end

#pragma mark - Swizzling Setup

/**
 * Helper function to swizzle a method on NSMenu.
 *
 * @param menuClass The NSMenu class
 * @param originalSel The original selector to swizzle
 * @param swizzledSel The replacement selector
 * @param methodName Human-readable method name for logging
 */
static void swizzleNSMenuMethod(Class menuClass,
                                SEL originalSel,
                                SEL swizzledSel,
                                const char *methodName)
{
  Method originalMethod = class_getInstanceMethod(menuClass, originalSel);
  Method swizzledMethod = class_getInstanceMethod(menuClass, swizzledSel);

  if (!originalMethod)
    {
      EAULOG(@"Eau: Cannot swizzle NSMenu -%s: original method not found", methodName);
      return;
    }

  if (!swizzledMethod)
    {
      EAULOG(@"Eau: Cannot swizzle NSMenu -%s: swizzled method not found", methodName);
      return;
    }

  // Prevent double-swizzling on bundle reload
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP)
    {
      EAULOG(@"Eau: NSMenu -%s already swizzled, skipping", methodName);
      return;
    }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  EAULOG(@"Eau: Swizzled NSMenu -%s for Macintosh menu support", methodName);
}

/**
 * Constructor function that runs when the theme bundle loads.
 *
 * Installs method swizzles on NSMenu to enable NSMacintoshInterfaceStyle
 * support with upstream libs-gui.
 */
__attribute__((constructor))
static void initNSMenuSwizzling(void)
{
  Class menuClass = objc_getClass("NSMenu");
  if (!menuClass)
    {
      EAULOG(@"Eau: Failed to get NSMenu class for swizzling");
      return;
    }

  EAULOG(@"Eau: Installing NSMenu swizzles for Macintosh interface style support");

  // Swizzle -menuChanged
  // Posts notification when menu changes reach the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(menuChanged),
                      @selector(eau_menuChanged),
                      "menuChanged");

  // Swizzle -setMain:
  // Posts notification when a menu becomes the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(setMain:),
                      @selector(eau_setMain:),
                      "setMain:");

  // Swizzle -display
  // Allows theme to hide menu window via proposedVisibility:forMenu:
  // and closes orphaned menu windows when a new dropdown is opened.
  swizzleNSMenuMethod(menuClass,
                      @selector(display),
                      @selector(eau_display),
                      "display");

  // Swizzle -displayTransient
  // Same orphaned-menu cleanup for transient menus (context menus,
  // torn-off menus, submenus of transient menus).
  swizzleNSMenuMethod(menuClass,
                      @selector(displayTransient),
                      @selector(eau_displayTransient),
                      "displayTransient");

  // Swizzle -trackWithEvent: on NSMenuView to count active tracking
  // sessions and run cleanup when tracking ends.
  Class menuViewClass = objc_getClass("NSMenuView");
  if (menuViewClass)
    {
      Method origTW = class_getInstanceMethod(menuViewClass,
                                              @selector(trackWithEvent:));
      if (origTW)
        {
          s_orig_trackWithEvent
            = (BOOL (*)(id, SEL, id))method_getImplementation(origTW);
          method_setImplementation(origTW, (IMP)s_eau_trackWithEvent);
        }
    }

  // Swizzle setFrameOrigin: and setFrame:display: on NSMenuPanel to clamp
  // menu windows to the bottom screen border. This catches ALL menu
  // positioning regardless of which code path is used.
  _eau_swizzleMenuWindowFrameMethods();
}
