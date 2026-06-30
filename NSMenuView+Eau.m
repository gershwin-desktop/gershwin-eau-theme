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

// Forward declare private NSMenuView methods we need
@interface NSMenuView (PrivateKnown)
- (CGFloat) yOriginForItem: (NSInteger)item;
- (CGFloat) heightForItem: (NSInteger)item;
- (CGFloat) totalHeight;
@end

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

// Original IMP for mouseDown:
static void (*s_orig_mouseDown)(id, SEL, id) = NULL;

static void s_eau_mouseDown(id self, SEL _cmd, NSEvent *event)
{
  s_orig_mouseDown(self, _cmd, event);
}

// Original IMP for trackWithEvent:
static BOOL (*s_orig_trackWithEvent_NSMenuView)(id, SEL, id) = NULL;

static BOOL s_eau_trackWithEvent(id self, SEL _cmd, NSEvent *event)
{
  return s_orig_trackWithEvent_NSMenuView(self, _cmd, event);
}

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
          // Try showing on the left side of the parent instead
          xPos = screenFrame.origin.x;
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

  // --- Swizzle trackWithEvent: (for edge autoscroll) ---
  {
    SEL sel = sel_registerName("trackWithEvent:");
    Method m = class_getInstanceMethod(menuViewClass, sel);
    if (m)
      {
        s_orig_trackWithEvent_NSMenuView = (void *)method_getImplementation(m);
        method_setImplementation(m, (IMP)s_eau_trackWithEvent);
        NSDebugLog(@"NSMenuView+Eau: Swizzled trackWithEvent: for edge autoscroll");
      }
  }
}
