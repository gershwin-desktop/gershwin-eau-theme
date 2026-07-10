// NSMenuView+Eau.m
// Eau Theme NSMenuView Extensions
//
// Custom submenu positioning and scrollable overflowing menu support.
// When a menu's total height exceeds the available screen space, the
// menu enters overflow mode: the window is resized to fill the screen
// and items are scrolled via a virtual viewport with no visible scrollbar,
// matching Mac OS X 10.5 (Leopard) behavior.

#import "Eau.h"
#import "EauMenuScrollManager.h"
#import "NSMenuView+Eau.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>
#import <X11/Xlib.h>

// Forward declare private NSMenuView methods we need
@interface NSMenuView (PrivateKnown)
- (CGFloat) yOriginForItem: (NSInteger)item;
- (CGFloat) heightForItem: (NSInteger)item;
- (CGFloat) totalHeight;
@end

// Accessors from NSMenu+Eau.m
NSMenuView *EauGetTrackedMenuView(void);
BOOL EauGetKeyboardNavActive(void);
void EauSetKeyboardNavActive(BOOL active);

#pragma mark - Scroll-Offset Swizzles

// Original IMP for rectOfItemAtIndex:
// We swizzle this to subtract the scroll offset, bringing items from
// content coordinates into viewport coordinates.  Points from the event
// system are already in viewport coordinates (the window clips to the
// visible viewport), so indexOfItemAtPoint: needs no separate swizzle.
static NSRect (*s_orig_rectOfItemAtIndex)(id, SEL, NSInteger) = NULL;

static NSRect s_eau_rectOfItemAtIndex(id self, SEL _cmd, NSInteger index)
{
  NSRect r = s_orig_rectOfItemAtIndex(self, _cmd, index);

  NSMenuView *menuView = (NSMenuView *)self;
  if (![menuView isHorizontal])
    {
      EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForMenuView: menuView];
      if (mgr && [mgr isScrolling])
        {
          r.origin.y -= [mgr scrollOffset];
        }
    }

  return r;
}

// Original IMP for sizeToFit:
static void (*s_orig_sizeToFit)(id, SEL) = NULL;

static void s_eau_sizeToFit(id self, SEL _cmd)
{
  s_orig_sizeToFit(self, _cmd);

  // After sizing, if we're in overflow mode, clamp the view height
  // back to the visible viewport so items don't extend past the window.
  NSMenuView *menuView = (NSMenuView *)self;
  if ([menuView isHorizontal]) return;

  EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForMenuView: menuView];
  if (mgr && [mgr isScrolling])
    {
      NSSize viewSize = [menuView frame].size;
      CGFloat visibleHeight = [mgr visibleHeight];
      if (viewSize.height > visibleHeight)
        {
          viewSize.height = visibleHeight;
          [menuView setFrameSize: viewSize];
        }
    }
  else
    {
      // No scroll manager yet.  The window frame may have been set
      // before the menu view was attached, so the swizzled window-
      // frame methods in NSMenu+Eau.m saw no menu view and silently
      // skipped overflow setup.  Run overflow detection *now* that
      // the view is definitely in the window.
      [EauMenuScrollManager setupOverflowForMenuView: menuView];
    }
}

// Original IMP for keyDown:
static void (*s_orig_keyDown)(id, SEL, id) = NULL;

static NSInteger s_eau_nextSelectableItem(NSMenuView *menuView, NSInteger from, NSInteger dir)
{
  NSMenu *menu = [menuView menu];
  NSInteger count = [menu numberOfItems];
  NSInteger i = from + dir;
  while (i >= 0 && i < count)
    {
      NSMenuItem *item = [menu itemAtIndex: i];
      if ([item isEnabled] && ![item isSeparatorItem])
        return i;
      i += dir;
    }
  return -1;
}

// Find the parent of a given submenu view by walking the attachedMenuView
// chain from the root tracking view.
// Warp the mouse cursor to the center of item `index` on `menuView`.
static void s_eau_warpToItem(NSMenuView *menuView, NSInteger index)
{
  if (index < 0) return;
  NSRect r = [menuView rectOfItemAtIndex: index];
  r = [menuView convertRect: r toView: nil];
  NSWindow *win = [menuView window];
  if (!win) return;
  NSPoint sp = [win convertBaseToScreen: r.origin];
  int cx = (int)(sp.x + r.size.width / 2);
  int cy = (int)(sp.y + r.size.height / 2);
  Display *dpy = XOpenDisplay(NULL);
  if (dpy)
    {
      XWarpPointer(dpy, None, DefaultRootWindow(dpy), 0, 0, 0, 0, cx, cy);
      XFlush(dpy);
      XCloseDisplay(dpy);
    }
}

// Switch to the adjacent menu title's dropdown: detach current, move
// highlight to prev/next, attach that title's submenu.
static void s_eau_switchToAdjacentMenu(NSMenuView *menuView, NSInteger dir)
{
  NSMenuView *root = EauGetTrackedMenuView();
  if (!root || ![root isHorizontal]) return;

  // Save before detachSubmenu clears it to -1.
  NSInteger cur = [root highlightedItemIndex];
  [root detachSubmenu];

  NSInteger next = s_eau_nextSelectableItem(root, cur >= 0 ? cur : (dir > 0 ? -1 : [[root menu] numberOfItems]), dir);
  if (next >= 0)
    {
      [root setHighlightedItemIndex: next];
      NSMenuItem *item = [[root menu] itemAtIndex: next];
      if (item && [item submenu] && [item isEnabled])
        {
          [root attachSubmenuForItemAtIndex: next];
        }
      s_eau_warpToItem(root, next);
    }
}

static void s_eau_keyDown(id self, SEL _cmd, NSEvent *event)
{
  NSString *chars = [event characters];
  NSUInteger mods = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;
  // Only reject if one of the standard modifier keys is pressed.
  // GNUstep may set additional bits (e.g. 0x800000) even when no
  // modifier key is physically held; we must ignore those.
  BOOL hasModifier = (mods & (NSShiftKeyMask | NSControlKeyMask
                              | NSAlternateKeyMask | NSCommandKeyMask
                              | NSAlphaShiftKeyMask)) != 0;
// NSLog(@"Eau+Menu: keyDown chars=%@ mods=0x%lx hasMod=%d self=%@",
//         chars, (unsigned long)mods, hasModifier, self);
  if ([chars length] == 0 || hasModifier)
    {
      s_orig_keyDown(self, _cmd, event);
      return;
    }

  unichar c = [chars characterAtIndex: 0];
  NSMenuView *menuView = (NSMenuView *)self;
  NSInteger cur = [menuView highlightedItemIndex];
  BOOL isHoriz = [menuView isHorizontal];
  NSInteger newIdx;

// NSLog(@"Eau+Menu: keyDown c=0x%04x cur=%ld horiz=%d isAttached=%d",
//         c, (long)cur, isHoriz, [menuView isAttached]);

  // Any keyboard navigation key activates keyboard-nav mode, which
  // suppresses mouse-moved events until the user clicks again.
  if (c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey
      || c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey
      || c == '\r' || c == '\n' || c == ' ' || c == 0x1B)
    {
      EauSetKeyboardNavActive(YES);
    }

  switch (c)
    {
      /* ── Up arrow ── */
      case NSUpArrowFunctionKey:
        if (isHoriz) return;                     // no-op on menu bar
        newIdx = s_eau_nextSelectableItem(menuView, cur >= 0 ? cur : 0, -1);
        // NSLog(@"Eau+Menu: Up cur=%ld newIdx=%ld", (long)cur, (long)newIdx);
        if (newIdx >= 0)
          {
            [menuView setHighlightedItemIndex: newIdx];
          }
        else if (cur >= 0 && [menuView isAttached])
          {
            // At the first item — close dropdown back to parent.
            NSMenuView *root = EauGetTrackedMenuView();
            NSMenuView *parent = nil;
            if (root && root != menuView)
              {
                NSMenuView *p = root;
                while (p)
                  {
                    NSMenuView *attached = [p attachedMenuView];
                    if (attached == menuView) { parent = p; break; }
                    p = attached;
                  }
              }
            NSMenu *parentMenu = [parent menu];
            NSMenu *childMenu = [menuView menu];
            NSInteger parentIdx = (parentMenu && childMenu)
              ? [parentMenu indexOfItemWithSubmenu: childMenu] : -1;
            [parent detachSubmenu];
            if (parentIdx >= 0)
              {
                [parent setHighlightedItemIndex: parentIdx];
                s_eau_warpToItem(parent, parentIdx);
              }
            [[menuView window] orderOut: nil];
          }
        return;

      /* ── Down arrow ── */
      case NSDownArrowFunctionKey:
        if (isHoriz)
          {
            if (cur < 0)
              {
                newIdx = s_eau_nextSelectableItem(menuView, -1, 1);
                // NSLog(@"Eau+Menu: Down first newIdx=%ld", (long)newIdx);
                if (newIdx >= 0) [menuView setHighlightedItemIndex: newIdx];
                return;
              }
            // Open dropdown for highlighted menu title
            NSMenuItem *item = [[menuView menu] itemAtIndex: cur];
            // NSLog(@"Eau+Menu: Down open submenu for idx=%ld item=%@ submenu=%d enabled=%d",
            //       (long)cur, [item title], [item submenu] != nil, [item isEnabled]);
            if (item && [item submenu] && [item isEnabled])
              {
                [menuView attachSubmenuForItemAtIndex: cur];
                s_eau_warpToItem(menuView, cur);
              }
          }
        else
          {
            newIdx = s_eau_nextSelectableItem(menuView, cur >= 0 ? cur : -1, 1);
            // NSLog(@"Eau+Menu: Down cur=%ld newIdx=%ld", (long)cur, (long)newIdx);
            if (newIdx >= 0)
              [menuView setHighlightedItemIndex: newIdx];
          }
        return;

      /* ── Right arrow ── */
      case NSRightArrowFunctionKey:
        if (isHoriz)
          {
            s_eau_switchToAdjacentMenu(menuView, 1);
          }
        else
          {
            if (cur >= 0)
              {
                NSMenuItem *item = [[menuView menu] itemAtIndex: cur];
                if (item && [item submenu] && [item isEnabled])
                  {
                    [menuView attachSubmenuForItemAtIndex: cur];
                    s_eau_warpToItem(menuView, cur);
                    return;
                  }
              }
            // No submenu (or no highlighted item) → next menu title
            s_eau_switchToAdjacentMenu(menuView, 1);
          }
        return;

      /* ── Left arrow ── */
      case NSLeftArrowFunctionKey:
        if (isHoriz)
          {
            s_eau_switchToAdjacentMenu(menuView, -1);
          }
        else
          {
            // If parent is the menu bar (horizontal), this is a root
            // dropdown — switch to previous title's dropdown.
            // If parent is another dropdown (vertical), this is a
            // submenu — close it and return to the parent.
            NSMenuView *parent = nil;
            NSMenuView *root = EauGetTrackedMenuView();
            if (root && root != menuView)
              {
                NSMenuView *p = root;
                while (p)
                  {
                    NSMenuView *attached = [p attachedMenuView];
                    if (attached == menuView) { parent = p; break; }
                    p = attached;
                  }
              }
            if (parent && ![parent isHorizontal])
              {
                // Submenu of another dropdown — close just this level.
                // Find which item in the parent owns this submenu.
                NSMenu *parentMenu = [parent menu];
                NSMenu *childMenu = [menuView menu];
                NSInteger parentIdx = (parentMenu && childMenu)
                  ? [parentMenu indexOfItemWithSubmenu: childMenu] : -1;
                [parent detachSubmenu];
                if (parentIdx >= 0)
                  [parent setHighlightedItemIndex: parentIdx];
                [[menuView window] orderOut: nil];
              }
            else if (root && [root isHorizontal])
              {
                // Root dropdown attached to menu bar — switch title.
                s_eau_switchToAdjacentMenu(menuView, -1);
              }
            else
              {
                // Standalone popup — close it.
                [NSApp abortModal];
              }
          }
        return;

      /* ── Enter / Space — perform action ── */
      case '\r':
      case '\n':
      case ' ':
        if (cur >= 0)
          {
            NSMenuItem *item = [[menuView menu] itemAtIndex: cur];
            if (item && [item submenu] && [item isEnabled])
              {
                // Item has submenu — open it instead of activating
                [menuView attachSubmenuForItemAtIndex: cur];
              }
            else
              {
                [[menuView menu] performActionForItemAtIndex: cur];
                [NSApp abortModal];
              }
          }
        return;

      /* ── Escape — close all menus ── */
      case 0x1B:
        {
          // Post a synthetic left-mouse-up at the front of the queue so
          // the tracking loop processes it immediately and exits.
          NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp
                                           location: NSZeroPoint
                                      modifierFlags: 0
                                          timestamp: [NSDate timeIntervalSinceReferenceDate]
                                       windowNumber: 0
                                            context: nil
                                        eventNumber: 0
                                         clickCount: 1
                                           pressure: 0.0];
          [NSApp postEvent: up atStart: YES];
        }
        return;
    }

  s_orig_keyDown(self, _cmd, event);
}

// Original IMP for mouseDown:
static void (*s_orig_mouseDown)(id, SEL, id) = NULL;

static void s_eau_mouseDown(id self, SEL _cmd, NSEvent *event)
{
  s_orig_mouseDown(self, _cmd, event);
}

// trackWithEvent: not swizzled here — NSMenu+Eau.m owns that swizzle
// for tracking-count management and keyboard event injection.

#pragma mark - setHighlightedItemIndex: Swizzle

static void (*s_orig_setHighlightedItemIndex)(id, SEL, NSInteger) = NULL;

static void s_eau_setHighlightedItemIndex(id self, SEL _cmd, NSInteger index)
{
  s_orig_setHighlightedItemIndex(self, _cmd, index);

  // Scroll the newly-highlighted item into view so the user can reach
  // items beyond the viewport by moving the mouse near the edge.
  // We guard against edge scrolling: during active edge scrolling the
  // edge-scroll timer (pollEdgeScroll) handles content positioning and
  // scroll-into-view would fight it, creating a feedback loop.
  NSMenuView *menuView = (NSMenuView *)self;
  EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForMenuView: menuView];
  if (mgr && [mgr isScrolling] && ![mgr isEdgeScrolling])
    {
      [mgr scrollItemAtIndexToVisible: index];
    }
}

#pragma mark - drawRect: Swizzle (scroll arrow indicators)

static void (*s_orig_drawRect)(id, SEL, NSRect) = NULL;

static void s_eau_drawRect(id self, SEL _cmd, NSRect dirtyRect)
{
  // Let the original draw all items first.
  s_orig_drawRect(self, _cmd, dirtyRect);

  // Overlay scroll-direction arrows on overflowing menus.
  NSMenuView *menuView = (NSMenuView *)self;
  if ([menuView isHorizontal]) return;

  EauMenuScrollManager *mgr = [EauMenuScrollManager scrollManagerForMenuView: menuView];
  if (mgr && [mgr isScrolling])
    {
      [mgr drawScrollIndicatorsInView: menuView];
    }
}

#pragma mark - Submenu Positioning

@implementation NSMenuView (EauTheme)

- (NSPoint)eau_locationForSubmenu:(NSMenu *)aSubmenu
{
  NSDebugLog(@"NSMenuView+Eau: eau_locationForSubmenu: called for submenu %@", aSubmenu);

  NSMenuView *menuView = (NSMenuView *)self;
  NSWindow *window = [menuView window];

  // Horizontal menu bar: position dropdown below the menu bar item.
  if ([menuView isHorizontal])
    {
      if (!window || !aSubmenu) return NSZeroPoint;

      // Find the item in this menu that has the submenu.
      NSMenu *myMenu = [menuView menu];
      NSInteger itemIndex = [myMenu indexOfItemWithSubmenu:aSubmenu];
      if (itemIndex < 0) return NSZeroPoint;

      // Get the item's rect in window coordinates, then screen.
      NSRect itemRect = [menuView rectOfItemAtIndex: itemIndex];
      itemRect = [menuView convertRect:itemRect toView:nil];
      NSPoint screenOrigin = [window convertBaseToScreen:itemRect.origin];

      // Get the submenu's window frame to know its height.
      NSRect subFrame = [[[aSubmenu menuRepresentation] window] frame];
      CGFloat subH = NSHeight(subFrame);
      if (subH < 1) subH = 100; // fallback if window not yet sized

      // X: same as the item's left edge
      // Y: place submenu's TOP at the item's BOTTOM in screen coords.
      //    In GNUstep screen coordinates (origin bottom-left), the item's
      //    bottom is screenOrigin.y, so we place the submenu origin at
      //    screenOrigin.y - subH to make its top align with item bottom.
      CGFloat yPos = screenOrigin.y - subH;
      // If the menu would extend past the bottom screen border, shift it up.
      if (yPos < 0)
        {
          NSDebugLog(@"NSMenuView+Eau: Horizontal menu extends past bottom border (yPos=%.1f), shifting up", yPos);
          yPos = 0;
        }
      // Clamp horizontally so the menu fits on screen.
      CGFloat subW = NSWidth(subFrame);
      if (subW < 1) subW = 100;
      NSScreen *menuScreen = [window screen];
      if (!menuScreen) menuScreen = [NSScreen mainScreen];
      if (menuScreen)
        {
          NSRect screenFrame = [menuScreen frame];
          if (screenOrigin.x + subW > NSMaxX(screenFrame))
            {
              screenOrigin.x = NSMaxX(screenFrame) - subW;
            }
          if (screenOrigin.x < screenFrame.origin.x)
            {
              screenOrigin.x = screenFrame.origin.x;
            }
        }
      NSDebugLog(@"NSMenuView+Eau: Horizontal pos for '%@': itemRect=%@ screenOrigin=%@ subH=%.1f → (%.1f, %.1f)",
            [aSubmenu title], NSStringFromRect(itemRect), NSStringFromPoint(screenOrigin),
            subH, screenOrigin.x, yPos);
      return NSMakePoint(screenOrigin.x, yPos);
    }

  // Vertical dropdown menu: position child submenu to the right, aligned
  // vertically with the parent item so the submenu's first item appears
  // at the same level as the item that triggered it.

  if (!window || !aSubmenu) return NSZeroPoint;

  // Find the item in THIS menu that has the submenu.
  NSMenu *myMenu = [menuView menu];
  NSInteger itemIndex = [myMenu indexOfItemWithSubmenu:aSubmenu];
  if (itemIndex < 0) return NSZeroPoint;

  // Get the item's rect in the view's coordinate system.
  // In overflow scrolling mode, rectOfItemAtIndex: already returns
  // viewport-adjusted coordinates (scroll offset subtracted).
  NSRect itemRect = [menuView rectOfItemAtIndex: itemIndex];
  CGFloat itemH = NSHeight(itemRect);

  itemRect = [menuView convertRect:itemRect toView:nil];
  NSPoint screenOrigin = [window convertBaseToScreen:itemRect.origin];

  // Get the submenu's window frame to know its height and width.
  NSRect subFrame = [[[aSubmenu menuRepresentation] window] frame];
  CGFloat subH = NSHeight(subFrame);
  if (subH < 1) subH = 100;
  CGFloat subW = NSWidth(subFrame);
  if (subW < 1) subW = 100;

  // X: right edge of parent window (no horizontal overlap)
  NSRect parentFrame = [window frame];
  CGFloat xPos = NSMaxX(parentFrame);

  // Y: align submenu's TOP edge with the parent item's TOP edge.
  // In GNUstep screen coords (bottom-left origin):
  //   item top = screenOrigin.y + itemH
  //   submenu origin (bottom-left) at: itemTop - subH
  CGFloat yPos = screenOrigin.y + itemH - subH;
  // If the menu would extend past the bottom screen border, shift it up.
  if (yPos < 0)
    {
      NSDebugLog(@"NSMenuView+Eau: Vertical submenu extends past bottom border (yPos=%.1f), shifting up", yPos);
      yPos = 0;
    }
  // If the menu would extend past the top screen border, shift it down.
  NSScreen *menuScreen = [window screen];
  if (!menuScreen) menuScreen = [NSScreen mainScreen];
  if (menuScreen)
    {
      NSRect screenFrame = [menuScreen frame];
      if (yPos + subH > NSMaxY(screenFrame))
        {
          yPos = NSMaxY(screenFrame) - subH;
        }
      // Clamp horizontally so the submenu fits on screen.
      if (xPos + subW > NSMaxX(screenFrame))
        {
          // Show on the left side of the parent instead
          xPos = NSMinX(parentFrame) - subW;
        }
      if (xPos + subW > NSMaxX(screenFrame))
        {
          xPos = NSMaxX(screenFrame) - subW;
        }
      if (xPos < screenFrame.origin.x)
        {
          xPos = screenFrame.origin.x;
        }
    }

  NSDebugLog(@"NSMenuView+Eau: Vertical pos for '%@': parentFrame=%@ itemScreen=%@ itemH=%.1f subH=%.1f → (%.1f, %.1f)",
        [aSubmenu title], NSStringFromRect(parentFrame), NSStringFromPoint(screenOrigin),
        itemH, subH, xPos, yPos);
  return NSMakePoint(xPos, yPos);
}

@end

#pragma mark - Swizzle Registration

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void)
{
  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass)
    {
      NSDebugLog(@"NSMenuView+Eau: ERROR - NSMenuView class not found");
      return;
    }

  // --- Swizzle locationForSubmenu: ---
  {
    SEL originalSelector = sel_registerName("locationForSubmenu:");
    SEL swizzledSelector = @selector(eau_locationForSubmenu:);
    Method originalMethod = class_getInstanceMethod(menuViewClass, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(menuViewClass, swizzledSelector);
    if (originalMethod && swizzledMethod)
      {
        IMP originalIMP = method_getImplementation(originalMethod);
        IMP swizzledIMP = method_getImplementation(swizzledMethod);
        if (originalIMP != swizzledIMP)
          {
            method_exchangeImplementations(originalMethod, swizzledMethod);
            NSDebugLog(@"NSMenuView+Eau: Swizzled locationForSubmenu:");
          }
      }
    else
      {
        NSDebugLog(@"NSMenuView+Eau: Could not swizzle locationForSubmenu: (orig=%p swiz=%p)",
              originalMethod, swizzledMethod);
      }
  }

  // --- Swizzle rectOfItemAtIndex: (for scroll offset) ---
  {
    SEL sel = sel_registerName("rectOfItemAtIndex:");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_rectOfItemAtIndex = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_rectOfItemAtIndex);
        NSDebugLog(@"NSMenuView+Eau: Swizzled rectOfItemAtIndex: for scroll support");
      }
  }

  // --- Swizzle sizeToFit (preserve overflow view height after relayout) ---
  {
    SEL sel = sel_registerName("sizeToFit");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_sizeToFit = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_sizeToFit);
        NSDebugLog(@"NSMenuView+Eau: Swizzled sizeToFit for overflow height preservation");
      }
  }

  // --- Swizzle setHighlightedItemIndex: (for scroll-into-view) ---
  {
    SEL sel = sel_registerName("setHighlightedItemIndex:");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_setHighlightedItemIndex = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_setHighlightedItemIndex);
        NSDebugLog(@"NSMenuView+Eau: Swizzled setHighlightedItemIndex: for scroll-into-view");
      }
  }

  // --- Swizzle drawRect: (overlay scroll-arrow indicators) ---
  {
    SEL sel = sel_registerName("drawRect:");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_drawRect = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_drawRect);
        NSDebugLog(@"NSMenuView+Eau: Swizzled drawRect: for scroll-arrow indicators");
      }
  }

  // --- Install keyDown: on NSMenuView (keyboard navigation) ---
  // NSMenuView inherits keyDown: from NSResponder.  We must *add* a new
  // method to NSMenuView (not patch NSResponder), otherwise our handler
  // fires on every NSView/NSResponder subclass that hasn't overridden
  // keyDown: — including NSView, MenuGradientView, etc.
  {
    SEL sel = @selector(keyDown:);
    Method nsresp = class_getInstanceMethod([NSResponder class], sel);
    if (nsresp)
      {
        s_orig_keyDown = (void *)method_getImplementation(nsresp);
        const char *enc = method_getTypeEncoding(nsresp);
        class_addMethod(menuViewClass, sel, (IMP)s_eau_keyDown, enc);
        // NSLog(@"Eau+Menu: Installed keyDown: on NSMenuView (orig=%p new=%p enc=%s)",
        //       s_orig_keyDown, s_eau_keyDown, enc);
      }
  }

  // --- Swizzle mouseDown: (for edge autoscroll start/stop) ---
  {
    SEL sel = sel_registerName("mouseDown:");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_mouseDown = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_mouseDown);
        NSDebugLog(@"NSMenuView+Eau: Swizzled mouseDown: for edge autoscroll");
      }
  }

}
