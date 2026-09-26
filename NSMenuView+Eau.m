// NSMenuView+Eau.m
// Scroll arrows on overflowing menus.
//
// The scrolling itself is behavior and lives in GershwinBehaviors.bundle
// (Behaviors/NSMenuView+GB.m, GBMenuScrollManager); the theme only draws
// the arrows that show content is hidden above or below.

#import <AppKit/AppKit.h>
#import <objc/runtime.h>

/* GBMenuScrollManager's interface, looked up by name so the theme still
   works without the bundle (then no menu ever scrolls and nothing is drawn). */
@interface NSObject (EauMenuScrollLookup)
+ (id)scrollManagerForMenuView:(NSMenuView *)menuView;
- (BOOL)isScrolling;
- (CGFloat)scrollOffset;
- (CGFloat)maxScrollOffset;
- (CGFloat)visibleHeight;
@end

static id EauScrollManagerForMenuView(NSMenuView *menuView)
{
  Class managerClass = NSClassFromString(@"GBMenuScrollManager");
  if (managerClass == Nil)
    return nil;
  id mgr = [managerClass scrollManagerForMenuView: menuView];
  return [mgr isScrolling] ? mgr : nil;
}

static void EauFillTriangle(NSPoint a, NSPoint b, NSPoint c)
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint: a];
  [path lineToPoint: b];
  [path lineToPoint: c];
  [path closePath];
  [path fill];
}

/* Small upward/downward triangles at the top/bottom edges of the view when
   there is content hidden off-screen.  Focus is already locked. */
static void EauDrawScrollIndicators(NSView *view, id mgr)
{
  CGFloat viewWidth = [view bounds].size.width;
  CGFloat scrollOffset = [mgr scrollOffset];
  CGFloat maxScroll = [mgr maxScrollOffset];
  CGFloat visibleHeight = [mgr visibleHeight];

  [[NSColor colorWithCalibratedWhite: 0.18 alpha: 1.0] set];

  CGFloat cx = viewWidth / 2.0; // centre of the menu

  // Top arrow (points up): content is hidden above the viewport.
  if (scrollOffset < maxScroll)
    {
      EauFillTriangle(NSMakePoint(cx - 4.0, visibleHeight - 8.0),
                      NSMakePoint(cx + 4.0, visibleHeight - 8.0),
                      NSMakePoint(cx, visibleHeight - 2.0));
    }

  // Bottom arrow (points down): content is hidden below the viewport.
  if (scrollOffset > 0)
    {
      EauFillTriangle(NSMakePoint(cx - 4.0, 7.0),
                      NSMakePoint(cx + 4.0, 7.0),
                      NSMakePoint(cx, 1.0));
    }
}

static void (*s_orig_drawRect)(id, SEL, NSRect) = NULL;

static void s_eau_drawRect(id self, SEL _cmd, NSRect dirtyRect)
{
  // Let the original draw all items first.
  s_orig_drawRect(self, _cmd, dirtyRect);

  // Overlay scroll-direction arrows on overflowing menus.
  NSMenuView *menuView = (NSMenuView *)self;
  if ([menuView isHorizontal]) return;

  id mgr = EauScrollManagerForMenuView(menuView);
  if (mgr)
    {
      EauDrawScrollIndicators(menuView, mgr);
    }
}

@implementation NSMenuView (EauScrollArrows)

+ (void)load
{
  Method m = class_getInstanceMethod(self, @selector(drawRect:));
  if (m)
    {
      s_orig_drawRect = (void (*)(id, SEL, NSRect))method_getImplementation(m);
      method_setImplementation(m, (IMP)s_eau_drawRect);
      NSDebugLog(@"NSMenuView+Eau: Swizzled drawRect: for scroll-arrow indicators");
    }
}

@end
