/*
   NSMenu+GB.m

   Swizzles NSMenu and related classes to enable NSMacintoshInterfaceStyle
   support with upstream (unmodified) libs-gui, under any theme.

   1. Post NSMacintoshMenuDidChangeNotification when the main menu changes,
      so GBMenuClient keeps Menu.app in sync
   2. Hide the in-app menu bar while Menu.app serves the global one
      (-display consults -[GSTheme proposedVisibility:forMenu:])
   3. Enforce the invariant that before a new menu panel is shown, every
      panel left open by an earlier interaction is closed (the exception
      is a submenu, whose parent chain stays put).  Upstream only tears
      the first-level dropdown down for NSWindows95InterfaceStyle, so
      under the Macintosh style orphaned panels used to stay mapped and
      wedge the menu bar.
   4. Clamp menu panels to the screen and scroll overflowing menus
      (Leopard-style) when a menu has more items than fit on screen
   5. Count active tracking sessions and feed scroll-wheel / keyboard
      events into the tracking loop

   The item blink after a click is a look, so it stays in the theme; it asks
   GBMenuTracking whether a menu is being tracked.
*/

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>
#import <objc/runtime.h>
#import <string.h>
#import <X11/Xlib.h>
#import <X11/Xutil.h>

#import "GBMenuScrollManager.h"
#import "GBMenuTracking.h"
#import "GBMenuWindowFilter.h"

/* Menu.app sizes its search panel and caches in user space, so the height up
   to which its windows are not dropdowns grows with the same scale factor
   GNUstep applies to them. */
static int _gb_menuUtilityHeightLimit(void)
{
  return GBMenuUtilityHeightLimit([[GSTheme theme] menuBarHeight],
                                  [[NSScreen mainScreen] userSpaceScaleFactor]);
}

/* ---- NSMenuPanel forward declaration (private) ---- */
@interface NSObject (GBMenuPanel)
- (id)_menu;
@end

/* Forward declaration of private NSMenuView methods used for
   coordinate calculations. These exist in GNUstep's NSMenuView.m. */
@interface NSMenuView (GBScrollHelper)
- (CGFloat) yOriginForItem: (NSInteger)item;
- (CGFloat) heightForItem: (NSInteger)item;
- (CGFloat) totalHeight;
@end

/* ---- Helper: find NSMenuView in an NSMenuPanel's content view hierarchy ---- */
static NSView *_gb_findMenuViewInView(NSView *view)
{
  if (view == nil) return nil;
  if ([view isKindOfClass: objc_getClass("NSMenuView")])
    {
      return view;
    }
  for (NSView *subview in [view subviews])
    {
      NSView *found = _gb_findMenuViewInView(subview);
      if (found) return found;
    }
  return nil;
}

static NSMenuView *_gb_findMenuViewInWindow(NSWindow *window)
{
  if (!window) return nil;
  NSView *contentView = [window contentView];
  if (!contentView) return nil;

  // NSMenuView is typically a direct subview of the content view, but some
  // apps (e.g. Menu.app's Command menu) wrap it in an intermediate NSView.
  // Recurse so the scroll manager is found regardless of nesting depth.
  return (NSMenuView *)_gb_findMenuViewInView(contentView);
}

/* ---- Overflow handling for tall menus ---- */

/**
 * Detect if the menu contained in `window` overflows the available screen
 * space and, if so, configure the scroll manager and resize the window.
 *
 * Returns YES if overflow mode was entered (window was resized).
 */
static BOOL _gb_handleMenuOverflow(NSWindow *window, NSRect *frame)
{
  NSMenuView *menuView = _gb_findMenuViewInWindow(window);
  if (!menuView) return NO;

  // Delegate the full overflow-detection / setup logic to the shared
  // class method on GBMenuScrollManager.  This method is still needed
  // because the caller (clamp helper) uses a modified frame pointer to
  // apply the window resize via the original IMP, avoiding re-entry.
  BOOL result = [GBMenuScrollManager setupOverflowForMenuView: menuView];
  if (result)
    {
      // The class method already resized the window and view.  Read the
      // new window frame so the caller can apply it via the original IMP
      // (the class method uses a swizzled setFrame: which would recurse
      // if we didn't go through the original IMP here).
      NSRect newFrame = [window frame];
      frame->size.height = newFrame.size.height;
      frame->origin.y = newFrame.origin.y;
    }
  return result;
}

/* ---- NSMenuPanel swizzles: clamp menu windows to screen bounds ---- */

// Shared bottom-clamp helper: if the window extends past the screen
// borders, shift it to fit entirely on screen.
// Also detects overflow and resizes the window if the menu is too tall.
// Uses the original setFrame:display: IMP to avoid recursion.
static void (*s_orig_menuWindowSetFrameDisplay)(id, SEL, NSRect, BOOL) = NULL;

static BOOL _gb_clampMenuWindowToScreenBounds(id window)
{
  NSRect frame = [window frame];
  NSScreen *screen = [window screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (!screen) return NO;

  NSRect screenFrame = [screen frame];
  BOOL needsClamp = NO;

  // Bottom edge - shift up
  if (frame.origin.y < screenFrame.origin.y)
    {
      frame.origin.y = screenFrame.origin.y;
      needsClamp = YES;
    }

  // Top edge - shift down
  if (NSMaxY(frame) > NSMaxY(screenFrame))
    {
      frame.origin.y = NSMaxY(screenFrame) - frame.size.height;
      needsClamp = YES;
    }

  // Left edge - shift right
  if (frame.origin.x < screenFrame.origin.x)
    {
      frame.origin.x = screenFrame.origin.x;
      needsClamp = YES;
    }

  // Right edge - shift left
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
    }

  // Now handle overflow: if the menu is too tall for the screen,
  // resize it and activate scrolling.
  if (_gb_handleMenuOverflow(window, &frame))
    {
      // Apply the overflow-resized frame
      if (s_orig_menuWindowSetFrameDisplay)
        s_orig_menuWindowSetFrameDisplay(window, @selector(setFrame:display:), frame, NO);
      return YES;
    }

  return needsClamp;
}

static void (*s_orig_menuWindowSetFrameOrigin)(id, SEL, NSPoint) = NULL;

static void s_gb_menuWindowSetFrameOrigin(id self, SEL _cmd, NSPoint aPoint)
{
  if (s_orig_menuWindowSetFrameOrigin)
    s_orig_menuWindowSetFrameOrigin(self, _cmd, aPoint);
  _gb_clampMenuWindowToScreenBounds(self);
}

static void s_gb_menuWindowSetFrameDisplay(id self, SEL _cmd, NSRect frameRect, BOOL flag)
{
  if (s_orig_menuWindowSetFrameDisplay)
    s_orig_menuWindowSetFrameDisplay(self, _cmd, frameRect, flag);
  _gb_clampMenuWindowToScreenBounds(self);
}

/* NSMenuPanel inherits both frame setters from NSWindow; replacing the
 * inherited Method would clamp (and scan for a menu view) every window in
 * the app, so the replacement is added to NSMenuPanel itself, which then
 * chains to the inherited implementation captured by the caller. */
static void _gb_overrideOnMenuPanel(Class menuPanelClass, Method m, IMP imp)
{
  if (!class_addMethod(menuPanelClass, method_getName(m), imp, method_getTypeEncoding(m)))
    method_setImplementation(m, imp);
}

static void _gb_swizzleMenuWindowFrameMethods(void)
{
  Class menuPanelClass = objc_getClass("NSMenuPanel");
  if (!menuPanelClass)
    {
      NSDebugLog(@"GershwinBehaviors: NSMenuPanel class not found, skipping menu window swizzles");
      return;
    }

  // Swizzle setFrameOrigin:
  SEL selOrigin = sel_registerName("setFrameOrigin:");
  Method mOrigin = class_getInstanceMethod(menuPanelClass, selOrigin);
  if (mOrigin)
    {
      s_orig_menuWindowSetFrameOrigin = (void (*)(id, SEL, NSPoint))method_getImplementation(mOrigin);
      _gb_overrideOnMenuPanel(menuPanelClass, mOrigin, (IMP)s_gb_menuWindowSetFrameOrigin);
      NSDebugLog(@"GershwinBehaviors: Swizzled NSMenuPanel setFrameOrigin: for bottom-screen clamping");
    }

  // Swizzle setFrame:display: (catches sizeToFit calls that bypass setFrameOrigin:)
  SEL selFrameDisplay = sel_registerName("setFrame:display:");
  Method mFrameDisplay = class_getInstanceMethod(menuPanelClass, selFrameDisplay);
  if (mFrameDisplay)
    {
      s_orig_menuWindowSetFrameDisplay = (void (*)(id, SEL, NSRect, BOOL))method_getImplementation(mFrameDisplay);
      _gb_overrideOnMenuPanel(menuPanelClass, mFrameDisplay, (IMP)s_gb_menuWindowSetFrameDisplay);
      NSDebugLog(@"GershwinBehaviors: Swizzled NSMenuPanel setFrame:display: for bottom-screen clamping");
    }
}

/* ---- Tracked windows + active tracking counter ---- */
static volatile int _gb_activeTrackingCount = 0;
static __weak NSMenuView *_gb_trackedMenuView = nil;
static BOOL _gb_keyboardNavActive = NO;
static Display *_gb_x11_display = NULL;

// Accessors for other compilation units (NSMenuView+GB.m) and the theme
NSMenuView *GBGetTrackedMenuView(void) { return _gb_trackedMenuView; }
BOOL GBGetKeyboardNavActive(void) { return _gb_keyboardNavActive; }
void GBSetKeyboardNavActive(BOOL active) { _gb_keyboardNavActive = active; }

@implementation GBMenuTracking
+ (BOOL)isTracking
{
  return _gb_activeTrackingCount > 0;
}
+ (NSMenuView *)trackedMenuView
{
  return _gb_trackedMenuView;
}
@end

static void _gb_ensureState(void)
{
  if (_gb_x11_display == NULL)
    _gb_x11_display = XOpenDisplay(NULL);
}

/* ---- Destroy ALL X11 "Menu" windows + their containers ---- */
static void _gb_destroyX11MenuWindows(void)
{
  _gb_ensureState();
  if (_gb_x11_display == NULL) return;

  /* Walk the X11 tree looking for GNUstep "Menu" windows in Normal
     state.  These are orphaned dropdowns.  We destroy BOTH the
     window AND its parent container, because the NSWindow's X11
     window is often a child of an unmanaged container (0x40f7ce
     style) that stays visible even after the child is destroyed. */
  Window root = DefaultRootWindow(_gb_x11_display);
  Window unused_root, unused_parent;
  Window *children = NULL;
  unsigned int nchildren = 0;

  if (!XQueryTree(_gb_x11_display, root, &unused_root, &unused_parent,
                  &children, &nchildren))
    return;

  int utilityLimit = _gb_menuUtilityHeightLimit();
  for (unsigned int i = 0; i < nchildren; i++)
    {
      Window w = children[i];
      XWindowAttributes attr;
      if (!XGetWindowAttributes(_gb_x11_display, w, &attr))
        continue;
      if (attr.map_state != IsViewable)
        continue;

      if (!GBIsMenuDropdownWindow(_gb_x11_display, w, attr.height,
                                  utilityLimit))
        continue;

      /* Found a visible GNUstep Menu window.  Destroy the parent
         container (w itself may be the child).  Walk up one level
         to find the actual parent container to destroy. */
      Window parent = w;
      Window root2 = None;
      Window *children2 = NULL;
      unsigned int nc2 = 0;
      if (XQueryTree(_gb_x11_display, parent, &root2, &parent,
                     &children2, &nc2))
        {
          if (children2) XFree(children2);
        }
      // parent now holds the actual parent of w

      // Also recurse into children to destroy any sub-windows
      // (deeper submenus)
      Window *subchildren = NULL;
      unsigned int nsub = 0;
      if (XQueryTree(_gb_x11_display, w, &unused_root, &unused_parent,
                     &subchildren, &nsub))
        {
          for (unsigned int j = 0; j < nsub; j++)
            {
              XDestroyWindow(_gb_x11_display, subchildren[j]);
            }
          if (subchildren) XFree(subchildren);
        }

      // Destroy w itself
      XDestroyWindow(_gb_x11_display, w);

      // If parent is not root, also destroy the parent container
      if (parent != root && parent != None)
        {
          XDestroyWindow(_gb_x11_display, parent);
        }
    }

  if (children) XFree(children);
  XSync(_gb_x11_display, False);
}

/* ---- Close-ahead enforcement: never show a new panel on top of old ones ----
 *
 * Upstream only tears down the first-level dropdown for
 * NSWindows95InterfaceStyle (see NSMenuView -trackWithEvent: teardown and
 * the mainWindowMenuView guard).  Under the Macintosh style an orphaned
 * panel stays mapped, swallows clicks and wedges the menu bar.
 *
 * TODO: Upstream to GNUstep - NSMenuView tracking teardown should close the
 * previous dropdown for NSMacintoshInterfaceStyle too.
 *
 * Invariant enforced here: before a new menu panel is displayed, every
 * visible panel that is NOT part of the new panel's own ancestor chain
 * (menu + supermenus) is closed first.  Submenu nesting is exempt by
 * construction: a submenu's parent menus are its supermenus, so they stay
 * in the keep-set.
 *
 * The AppKit-level pass only closes panels GNUstep still reports visible.
 * During a fast sweep over the menu bar the previous dropdown is already
 * marked hidden by the tracking loop while its X11 window is still mapped
 * (the original wedge), so a second pass withdraws stale panels directly
 * at the X11 level regardless of the AppKit visibility flag.
 */
static void _gb_closeStaleMenuPanelsForMenu(NSMenu *openingMenu)
{
  if (openingMenu == nil) return;

  Class panelClass = objc_getClass("NSMenuPanel");
  if (panelClass == nil) return;

  /* NOTE: we deliberately do NOT iterate [NSApp windows] here.  GNUstep menu
   * panels have is_released_when_closed set, so the tracking loop frees them;
   * a panel that appears in [NSApp windows] can already be deallocated (its
   * memory reused - the freed-object pattern fills it with the NSMenuPanel
   * class pointer), and messaging it then SIGSEGVs.  The stale-panel "wedge"
   * is an X11-mapping problem, so the X11-level withdrawal below is the
   * correct and crash-free way to fix it.
   */

  /* X11-level fallback: withdraw every still-mapped "Menu" dropdown window
     that is not part of the opening menu's keep-set.  AppKit's visibility
     flag is not consulted here because the stale panel is typically already
     flagged hidden by the tracking loop while its X11 window remains mapped
     (that is the wedge this enforcement exists to prevent).  Withdrawing,
     rather than destroying, keeps the cached NSMenuPanel window usable for
     later re-display.
     The keep-set is built from openingMenu's own window chain (menus, which
     are retained by the menu system and cannot dangle), NOT from [NSApp
     windows] (which can contain freed panels). */
  _gb_ensureState();
  if (_gb_x11_display == NULL) return;

  NSMutableSet *keepXids = [NSMutableSet set];
  {
    NSMenu *km = openingMenu;
    while (km != nil)
      {
        NSWindow *pw = [km window];
        if (pw != nil)
          {
            unsigned long xid = (unsigned long)[pw windowRef];
            if (xid != 0)
              [keepXids addObject: [NSNumber numberWithUnsignedLong: xid]];
          }
        km = [km supermenu];
      }
  }

  Window root = DefaultRootWindow(_gb_x11_display);
  Window unused_root, unused_parent;
  Window *children = NULL;
  unsigned int nchildren = 0;

  if (!XQueryTree(_gb_x11_display, root, &unused_root, &unused_parent,
                  &children, &nchildren))
    return;

  int utilityLimit = _gb_menuUtilityHeightLimit();
  for (unsigned int i = 0; i < nchildren; i++)
    {
      Window w = children[i];
      XWindowAttributes attr;
      if (!XGetWindowAttributes(_gb_x11_display, w, &attr))
        continue;

      if (attr.map_state != IsViewable)
        continue;

      if (!GBIsMenuDropdownWindow(_gb_x11_display, w, attr.height,
                                  utilityLimit))
        continue;

      if ([keepXids containsObject: [NSNumber numberWithUnsignedLong: (unsigned long)w]])
        continue;

      NSDebugLog(@"GB+Menu: withdrawing stale dropdown X window 0x%lx "
                 "before opening %@", (unsigned long)w, openingMenu);
      XWithdrawWindow(_gb_x11_display, w,
                      XScreenNumberOfScreen(attr.screen));

      /* Withdraw the parent too: GNUstep may reparent the NSWindow's X11
         window under an unmanaged container that stays visible on its own. */
      Window parent = w;
      Window *children2 = NULL;
      unsigned int nc2 = 0;
      if (XQueryTree(_gb_x11_display, w, &unused_root, &parent,
                     &children2, &nc2))
        {
          if (children2) XFree(children2);
        }
      if (parent != root && parent != None)
        XWithdrawWindow(_gb_x11_display, parent,
                        XScreenNumberOfScreen(attr.screen));
    }

  if (children) XFree(children);
  XSync(_gb_x11_display, False);
}

/* ---- NSMenuPanel orderFrontRegardless swizzle ---- */

static void (*s_orig_menuPanelOrderFrontRegardless)(id, SEL) = NULL;

static void s_gb_menuPanelOrderFrontRegardless(id self, SEL _cmd)
{
  NSMenu *menu = [(id)self _menu];
  if (menu != nil)
    _gb_closeStaleMenuPanelsForMenu(menu);
  if (s_orig_menuPanelOrderFrontRegardless)
    s_orig_menuPanelOrderFrontRegardless(self, _cmd);
}

/* ---- trackWithEvent: swizzle (increment/decrement, then cleanup) ---- */

static BOOL (*s_orig_trackWithEvent)(id, SEL, id) = NULL;

static BOOL s_gb_trackWithEvent(id self, SEL _cmd, NSEvent *event)
{
  _gb_activeTrackingCount++;
  _gb_trackedMenuView = (NSMenuView *)self;
  BOOL result = NO;
  @try
    {
      if (s_orig_trackWithEvent)
        result = s_orig_trackWithEvent(self, _cmd, event);
    }
  @catch (NSException *e) {}
  _gb_activeTrackingCount--;
  if (_gb_activeTrackingCount == 0)
    _gb_trackedMenuView = nil;
  NSDebugLog(@"GB+Menu: trackWithEvent end tracking=%d",
             _gb_activeTrackingCount);
  _gb_destroyX11MenuWindows();
  return result;
}

/* ---- nextEventMatchingMask: swizzle for scroll wheel during tracking ---- */

static NSEvent* (*s_orig_nextEventMatchingMask)(id, SEL, NSUInteger, NSDate*, NSString*, BOOL) = NULL;

/* Find the scroll manager for the menu currently being tracked.
 *
 * The scroll manager is associated with the MENU VIEW's window (and the view
 * itself), set up by setupOverflowForMenuView: when the menu was displayed.
 * [NSApp keyWindow] is NOT reliable during tracking: GNUstep menu panels are
 * not key windows, and in Menu.app (global menu bar) the key window is often
 * nil while a dropdown is open.  So walk the tracked view's attached-submenu
 * chain (same logic as the keyboard-navigation code) to the deepest OPEN
 * submenu and look the manager up on its window/view.  Fall back to the key
 * window for non-menu apps where that works.
 */
static GBMenuScrollManager *_gb_activeScrollManager(void)
{
  if (_gb_activeTrackingCount <= 0) return nil;

  NSMenuView *view = _gb_trackedMenuView;
  while (view)
    {
      NSWindow *w = [view window];
      if (w)
        {
          GBMenuScrollManager *mgr = [GBMenuScrollManager scrollManagerForWindow: w];
          if (!mgr)
            {
              mgr = [GBMenuScrollManager scrollManagerForMenuView: view];
            }
          if (mgr) return mgr;
        }
      NSMenuView *attached = [view attachedMenuView];
      NSWindow *aw = [attached window];
      if (!attached || !aw || ![aw isVisible]) break; // closed submenu
      view = attached;
    }

  // Fallback: some apps make the menu panel the key window.
  NSWindow *keyWindow = [NSApp keyWindow];
  if (keyWindow)
    {
      GBMenuScrollManager *mgr = [GBMenuScrollManager scrollManagerForWindow: keyWindow];
      if (!mgr)
        {
          NSMenuView *menuView = _gb_findMenuViewInWindow(keyWindow);
          if (menuView)
            {
              mgr = [GBMenuScrollManager scrollManagerForMenuView: menuView];
            }
        }
      if (mgr) return mgr;
    }
  return nil;
}

static NSEvent* s_gb_nextEventMatchingMask(id self, SEL _cmd, NSUInteger mask, NSDate *date, NSString *mode, BOOL dequeue)
{
  // During menu tracking, add scroll wheel and keyboard events to the mask
  // so we can process them in the tracking loop.
  if (_gb_activeTrackingCount > 0)
    {
      NSDebugLog(@"GB+Menu: nextEvent adding KeyDown mask");
      mask |= NSScrollWheelMask;
      mask |= NSKeyDownMask;
    }

  NSEvent *event = s_orig_nextEventMatchingMask(self, _cmd, mask, date, mode, dequeue);

  // When keyboard navigation is active, ignore mouse-moved events so the
  // tracking loop doesn't re-evaluate highlight based on stale cursor position.
  if (_gb_keyboardNavActive && event && [event type] == NSMouseMoved)
    {
      // Discard and fetch the next event (up to a limit to avoid infinite loop).
      int limit = 50;
      while (limit-- > 0)
        {
          event = s_orig_nextEventMatchingMask(self, _cmd, mask, date, mode, dequeue);
          if (!event || [event type] != NSMouseMoved)
            break;
        }
    }
  // Any mouse click deactivates keyboard nav.
  if (event && ([event type] == NSLeftMouseDown || [event type] == NSRightMouseDown
                || [event type] == NSOtherMouseDown))
    {
      _gb_keyboardNavActive = NO;
    }

  if (event && _gb_activeTrackingCount > 0)
    {
      // --- Edge scrolling: poll mouse position and scroll if near edge ---
      // We do this on EVERY event during tracking because NSTimer-based
      // edge scrolling doesn't fire reliably in NSEventTrackingRunLoopMode
      // on this GNUstep version.  pollEdgeScroll has its own throttle.
      {
        GBMenuScrollManager *mgr = _gb_activeScrollManager();
        if (mgr)
          {
            [mgr pollEdgeScroll];
          }
      }

      // --- Scroll wheel handling ---
      if ([event type] == NSScrollWheel)
        {
          GBMenuScrollManager *mgr = _gb_activeScrollManager();
          if (mgr && [mgr isScrolling])
            {
              CGFloat deltaY = [event deltaY];
              [mgr scrollByDelta: deltaY];
            }
        }

      // --- Keyboard navigation (arrows, Enter, Escape) ---
      if ([event type] == NSKeyDown && _gb_trackedMenuView)
        {
          // Route to deepest OPEN submenu, or top-level tracking view.
          // GNUstep's detachSubmenu doesn't clear _attachedMenu, so
          // attachedMenuView may return a closed submenu.  Check the
          // submenu window's visibility to skip detached-but-not-cleared
          // submenus.
          NSMenuView *target = _gb_trackedMenuView;
          NSMenuView *attached = [target attachedMenuView];
          while (attached)
            {
              NSWindow *w = [attached window];
              if (!w || ![w isVisible]) break; // closed
              target = attached;
              attached = [target attachedMenuView];
            }
          // NSLog(@"GB+Menu: key '%@' tracking=%d target=%@ horiz=%d cur=%ld",
          //       [event characters], _gb_activeTrackingCount,
          //       target, [target isHorizontal],
          //       (long)[target highlightedItemIndex]);
          [target keyDown: event];
        }
    }

  return event;
}

static void GBInstallNSMenuSwizzles(void);

@implementation NSMenu (GBBehaviors)

+ (void)load
{
  GBInstallNSMenuSwizzles();
}

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
 *
 * TODO: Upstream to GNUstep - NSMenu -menuChanged/-setMain: should tell the
 * theme about main-menu changes for every interface style, not only Windows95.
 */
- (void)gb_menuChanged
{
  // Call original implementation (handles propagation and flag setting)
  [self gb_menuChanged];

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
- (void)gb_setMain:(BOOL)isMain
{
  // Call original implementation
  [self gb_setMain:isMain];

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
 * menu bar (Menu.app).
 *
 * TODO: Upstream to GNUstep - NSMenu -display should honor
 * -[GSTheme proposedVisibility:forMenu:] instead of only reporting it.
 */
- (void)gb_display
{
  // Let theme control visibility
  // The theme's proposedVisibility:forMenu: returns NO for the main menu
  // when Menu.app is available, hiding the in-app menu bar
  if (![[GSTheme theme] proposedVisibility:YES forMenu:self])
    {
      return;
    }

  // Call original implementation
  [self gb_display];
}

/**
 * Swizzled -displayTransient implementation.
 *
 * Pass-through for transient menus (context menus, torn-off menus, etc.).
 * Bottom-screen clamping is handled by the NSMenuPanel setFrameOrigin:
 * swizzle which catches all menu window positioning.
 */
- (void)gb_displayTransient
{
  // Same close-ahead as gb_display/orderFrontRegardless: transient
  // panels are shown via _bWindow orderFront:, which bypasses the
  // NSMenuPanel orderFrontRegardless swizzle, so enforce here too.
  _gb_closeStaleMenuPanelsForMenu(self);
  [self gb_displayTransient];
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
      NSDebugLog(@"GershwinBehaviors: Cannot swizzle NSMenu -%s: original method not found", methodName);
      return;
    }

  if (!swizzledMethod)
    {
      NSDebugLog(@"GershwinBehaviors: Cannot swizzle NSMenu -%s: swizzled method not found", methodName);
      return;
    }

  // Prevent double-swizzling on bundle reload
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP)
    {
      NSDebugLog(@"GershwinBehaviors: NSMenu -%s already swizzled, skipping", methodName);
      return;
    }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  NSDebugLog(@"GershwinBehaviors: Swizzled NSMenu -%s for Macintosh menu support", methodName);
}

/* Runs from +load when the bundle loads.  Installs method swizzles on NSMenu
 * to enable NSMacintoshInterfaceStyle support with upstream libs-gui. */
static void GBInstallNSMenuSwizzles(void)
{
  Class menuClass = objc_getClass("NSMenu");
  if (!menuClass)
    {
      NSDebugLog(@"GershwinBehaviors: Failed to get NSMenu class for swizzling");
      return;
    }

  NSDebugLog(@"GershwinBehaviors: Installing NSMenu swizzles for Macintosh interface style support");

  // Swizzle -menuChanged
  // Posts notification when menu changes reach the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(menuChanged),
                      @selector(gb_menuChanged),
                      "menuChanged");

  // Swizzle -setMain:
  // Posts notification when a menu becomes the main menu
  swizzleNSMenuMethod(menuClass,
                      @selector(setMain:),
                      @selector(gb_setMain:),
                      "setMain:");

  // Swizzle -display
  // Allows theme to hide menu window via proposedVisibility:forMenu:
  // and closes orphaned menu windows when a new dropdown is opened.
  swizzleNSMenuMethod(menuClass,
                      @selector(display),
                      @selector(gb_display),
                      "display");

  // Swizzle -displayTransient
  // Same orphaned-menu cleanup for transient menus (context menus,
  // torn-off menus, submenus of transient menus).
  swizzleNSMenuMethod(menuClass,
                      @selector(displayTransient),
                      @selector(gb_displayTransient),
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
          method_setImplementation(origTW, (IMP)s_gb_trackWithEvent);
        }
    }

  // Swizzle setFrameOrigin: and setFrame:display: on NSMenuPanel to clamp
  // menu windows to the bottom screen border. This catches ALL menu
  // positioning regardless of which code path is used.
  _gb_swizzleMenuWindowFrameMethods();

  // Swizzle NSMenuPanel orderFrontRegardless to enforce the invariant that
  // no new menu panel is ever shown on top of panels left open by an earlier
  // interaction (only the new panel's own submenu chain stays open).  Every
  // dropdown/submenu/popup display ends in orderFrontRegardless on the
  // NSMenuPanel (_aWindow), so this is the single choke point for regular
  // (non-transient) panels.
  {
    Class menuPanelClass = objc_getClass("NSMenuPanel");
    if (menuPanelClass)
      {
        Method m = class_getInstanceMethod(menuPanelClass,
                                           @selector(orderFrontRegardless));
        if (m)
          {
            s_orig_menuPanelOrderFrontRegardless
              = (void (*)(id, SEL))method_getImplementation(m);
            method_setImplementation(m,
              (IMP)s_gb_menuPanelOrderFrontRegardless);
            NSDebugLog(@"GershwinBehaviors: Swizzled NSMenuPanel orderFrontRegardless for stale-panel close-ahead");
          }
      }
  }

  // Swizzle nextEventMatchingMask:untilDate:inMode:dequeue: on NSApplication
  // to add scroll wheel support during menu tracking.
  {
    Class appClass = objc_getClass("NSApplication");
    if (appClass)
      {
        SEL sel = sel_registerName("nextEventMatchingMask:untilDate:inMode:dequeue:");
        Method m = class_getInstanceMethod(appClass, sel);
        if (m)
          {
            {
              // Use memcpy for type-punning to avoid -Wincompatible-function-pointer-types
              IMP imp = method_getImplementation(m);
              memcpy(&s_orig_nextEventMatchingMask, &imp, sizeof(s_orig_nextEventMatchingMask));
            }
            method_setImplementation(m, (IMP)s_gb_nextEventMatchingMask);
            NSDebugLog(@"GershwinBehaviors: Swizzled NSApplication nextEventMatchingMask: for scroll wheel menu support");
          }
      }
  }
}
