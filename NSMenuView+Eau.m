// NSMenuView+Eau.m
// Eau Theme NSMenuView Extensions

#import "Eau.h"
#import "NSMenuView+Eau.h"
#import <AppKit/NSMenuView.h>
#import <objc/runtime.h>

@implementation NSMenuView (EauTheme)

- (NSPoint)eau_locationForSubmenu:(NSMenu *)aSubmenu
{
  EAULOG(@"NSMenuView+Eau: eau_locationForSubmenu: called for submenu %@", aSubmenu);

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
      NSRect itemRect = [menuView rectOfItemAtIndex:itemIndex];
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
          EAULOG(@"NSMenuView+Eau: Horizontal menu extends past bottom border (yPos=%.1f), shifting up", yPos);
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
      EAULOG(@"NSMenuView+Eau: Horizontal pos for '%@': itemRect=%@ screenOrigin=%@ subH=%.1f → (%.1f, %.1f)",
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

  // Get the item's rect in window coordinates, then screen.
  NSRect itemRect = [menuView rectOfItemAtIndex:itemIndex];
  itemRect = [menuView convertRect:itemRect toView:nil];
  NSPoint screenOrigin = [window convertBaseToScreen:itemRect.origin];
  CGFloat itemH = NSHeight(itemRect);

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
  // This makes the submenu's first row of items appear level with
  // the parent item.
  CGFloat yPos = screenOrigin.y + itemH - subH;
  // If the menu would extend past the bottom screen border, shift it up.
  if (yPos < 0)
    {
      EAULOG(@"NSMenuView+Eau: Vertical submenu extends past bottom border (yPos=%.1f), shifting up", yPos);
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

  EAULOG(@"NSMenuView+Eau: Vertical pos for '%@': parentFrame=%@ itemScreen=%@ itemH=%.1f subH=%.1f → (%.1f, %.1f)",
        [aSubmenu title], NSStringFromRect(parentFrame), NSStringFromPoint(screenOrigin),
        itemH, subH, xPos, yPos);
  return NSMakePoint(xPos, yPos);
}

@end

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuViewSwizzling(void) {
  // NSLog(@"NSMenuView+Eau: Constructor called - setting up swizzling");

  Class menuViewClass = objc_getClass("NSMenuView");
  if (!menuViewClass) {
    EAULOG(@"NSMenuView+Eau: ERROR - NSMenuView class not found");
    return;
  }

  // Swizzle locationForSubmenu: with eau_locationForSubmenu:
  SEL originalSelector = sel_registerName("locationForSubmenu:");
  SEL swizzledSelector = @selector(eau_locationForSubmenu:);

  Method originalMethod = class_getInstanceMethod(menuViewClass, originalSelector);
  Method swizzledMethod = class_getInstanceMethod(menuViewClass, swizzledSelector);

  if (!originalMethod) {
    EAULOG(@"NSMenuView+Eau: ERROR - Could not find original locationForSubmenu: method");
    return;
  }

  if (!swizzledMethod) {
    EAULOG(@"NSMenuView+Eau: ERROR - Could not find eau_locationForSubmenu: method on NSMenuView");
    return;
  }

  // Avoid double-swizzling: if the IMPs are already the same, do nothing.
  IMP originalIMP = method_getImplementation(originalMethod);
  IMP swizzledIMP = method_getImplementation(swizzledMethod);
  if (originalIMP == swizzledIMP) {
    EAULOG(@"NSMenuView+Eau: Swizzling skipped - implementations already identical");
    return;
  }

  method_exchangeImplementations(originalMethod, swizzledMethod);
  // NSLog(@"NSMenuView+Eau: Successfully swizzled locationForSubmenu: with eau_locationForSubmenu:");
}
