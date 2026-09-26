/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauDrawer.h"
#import "EauDrawerGeometry.h"
#import "AppearanceMetrics.h"
#import "Eau.h"
#import <objc/runtime.h>

/* GSDrawerWindow is private to libs-gui; these are its own methods. */
@interface NSWindow (EauDrawerWindowPrivate)
- (NSDrawer *) drawer;
- (NSBox *) container;
- (NSRect) frameFromParentWindowFrameInState: (NSInteger)state;
- (void) configureContainer: (NSRect)contentRect;
- (void) slideOpen: (BOOL)opening onEdge: (NSRectEdge)edge;
@end

static Class EAUDrawerWindowClass(void)
{
  static Class cls = Nil;
  static BOOL looked = NO;
  if (!looked)
    {
      cls = NSClassFromString(@"GSDrawerWindow");
      looked = YES;
    }
  return cls;
}

BOOL EauIsDrawerWindow(NSWindow *window)
{
  Class cls = EAUDrawerWindowClass();
  return cls != Nil && [window isKindOfClass: cls];
}

NSRectEdge EauDrawerEdgeOfWindow(NSWindow *window)
{
  return [[window drawer] edge];
}

/* The drawer's outline in view coordinates (y up), with the two corners
 * away from the parent rounded like the outline the window manager cuts. */
static NSBezierPath *EAUDrawerOutline(NSRect r, NSRectEdge edge, CGFloat radius)
{
  BOOL roundLeft = edge == NSMinXEdge || edge == NSMinYEdge || edge == NSMaxYEdge;
  BOOL roundRight = edge == NSMaxXEdge || edge == NSMinYEdge || edge == NSMaxYEdge;
  BOOL roundBottom = edge == NSMinYEdge || edge == NSMinXEdge || edge == NSMaxXEdge;
  BOOL roundTop = edge == NSMaxYEdge || edge == NSMinXEdge || edge == NSMaxXEdge;
  CGFloat bl = (roundBottom && roundLeft) ? radius : 0;
  CGFloat br = (roundBottom && roundRight) ? radius : 0;
  CGFloat tr = (roundTop && roundRight) ? radius : 0;
  CGFloat tl = (roundTop && roundLeft) ? radius : 0;
  NSBezierPath *p = [NSBezierPath bezierPath];

  [p moveToPoint: NSMakePoint(NSMinX(r) + bl, NSMinY(r))];
  [p lineToPoint: NSMakePoint(NSMaxX(r) - br, NSMinY(r))];
  if (br > 0)
    [p appendBezierPathWithArcFromPoint: NSMakePoint(NSMaxX(r), NSMinY(r))
                                toPoint: NSMakePoint(NSMaxX(r), NSMinY(r) + br) radius: br];
  [p lineToPoint: NSMakePoint(NSMaxX(r), NSMaxY(r) - tr)];
  if (tr > 0)
    [p appendBezierPathWithArcFromPoint: NSMakePoint(NSMaxX(r), NSMaxY(r))
                                toPoint: NSMakePoint(NSMaxX(r) - tr, NSMaxY(r)) radius: tr];
  [p lineToPoint: NSMakePoint(NSMinX(r) + tl, NSMaxY(r))];
  if (tl > 0)
    [p appendBezierPathWithArcFromPoint: NSMakePoint(NSMinX(r), NSMaxY(r))
                                toPoint: NSMakePoint(NSMinX(r), NSMaxY(r) - tl) radius: tl];
  [p lineToPoint: NSMakePoint(NSMinX(r), NSMinY(r) + bl)];
  if (bl > 0)
    [p appendBezierPathWithArcFromPoint: NSMakePoint(NSMinX(r), NSMinY(r))
                                toPoint: NSMakePoint(NSMinX(r) + bl, NSMinY(r)) radius: bl];
  [p closePath];
  return p;
}

BOOL EauDrawDrawerBackground(NSView *view, NSRect rect)
{
  NSWindow *window = [view window];
  NSRectEdge edge;
  NSRectEdge seam;
  NSRect bounds;
  NSColor *surface;
  NSGradient *shadow;
  CGFloat angle;
  CGFloat y;

  if (!EauIsDrawerWindow(window))
    {
      return NO;
    }
  edge = EauDrawerEdgeOfWindow(window);
  seam = [EauDrawerGeometry seamEdgeForEdge: edge];
  bounds = [view bounds];

  /* A shade darker than the window it sits behind, so it reads as a tray
   * pulled out from under it. */
  surface = [[NSColor windowBackgroundColor] shadowWithLevel: 0.07];
  [surface setFill];
  NSRectFill(rect);

  /* A fine brushed texture: every other row a touch darker, running along
   * the drawer's length. */
  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.025] setFill];
  if (edge == NSMinXEdge || edge == NSMaxXEdge)
    {
      for (y = NSMinY(bounds); y < NSMaxY(bounds); y += 2.0)
        NSRectFillUsingOperation(NSMakeRect(NSMinX(bounds), y, NSWidth(bounds), 1.0),
                                 NSCompositeSourceOver);
    }
  else
    {
      for (y = NSMinX(bounds); y < NSMaxX(bounds); y += 2.0)
        NSRectFillUsingOperation(NSMakeRect(y, NSMinY(bounds), 1.0, NSHeight(bounds)),
                                 NSCompositeSourceOver);
    }

  /* The window casts a soft shadow onto the drawer along the seam. */
  shadow = [[NSGradient alloc]
             initWithStartingColor: [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.22]
                       endingColor: [NSColor colorWithCalibratedWhite: 0.0 alpha: 0.0]];
  switch (seam)
    {
      case NSMinXEdge: angle = 0; break;
      case NSMaxXEdge: angle = 180; break;
      case NSMinYEdge: angle = 90; break;
      default:         angle = 270; break;
    }
  {
    NSRect band = bounds;
    CGFloat depth = METRICS_DRAWER_SEAM_SHADOW;
    NSRect remainder;
    NSDivideRect(bounds, &band, &remainder, depth, seam);
    [shadow drawInRect: band angle: angle];
  }

  /* A darker rim round the outer sides; the seam side stays open, the
   * window's own edge closes it. */
  [[surface shadowWithLevel: 0.35] setStroke];
  {
    NSBezierPath *rim = EAUDrawerOutline(NSInsetRect(bounds, 0.5, 0.5), edge,
                                         METRICS_DRAWER_CORNER_RADIUS);
    [rim setLineWidth: 1.0];
    [rim stroke];
  }
  return YES;
}

#pragma mark - The drawer's content size

/* What the application asked the drawer's content to be.  libs-gui keeps
 * no such value: -contentSize is the drawer window's size, which the
 * theme's frame then makes larger by the margins, so reading it back would
 * grow the drawer on every placement, and -setContentView: shrinks the
 * view to the box before passing its size on.  Kept on the NSDrawer. */
static char EAUDrawerContentSizeKey;
static BOOL EAUSettingContentView = NO;

static void EAURecordContentSize(NSDrawer *drawer, NSSize size)
{
  objc_setAssociatedObject(drawer, &EAUDrawerContentSizeKey, [NSValue valueWithSize: size],
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* Until the application sets one, the size the drawer was made with: its
 * window still has it when the theme first places the drawer. */
static NSSize EAUContentSizeOfDrawer(NSDrawer *drawer)
{
  NSValue *size = objc_getAssociatedObject(drawer, &EAUDrawerContentSizeKey);
  if (size == nil)
    {
      EAURecordContentSize(drawer, [drawer contentSize]);
      return [drawer contentSize];
    }
  return [size sizeValue];
}

@interface EauDrawerSwizzles : NSObject
@end

@implementation EauDrawerSwizzles

- (void) eau_setContentSize: (NSSize)size
{
  if (!EAUSettingContentView)
    {
      EAURecordContentSize((NSDrawer *)self, size);
    }
  [self eau_setContentSize: size];
}

- (void) eau_setContentView: (NSView *)view
{
  if (view != nil)
    {
      EAURecordContentSize((NSDrawer *)self, [view frame].size);
    }
  EAUSettingContentView = YES;
  [self eau_setContentView: view];
  EAUSettingContentView = NO;
}

@end

#pragma mark - GSDrawerWindow

@interface EauDrawerWindowSwizzles : NSObject
@end

@implementation EauDrawerWindowSwizzles

static void EAUDrawerSwizzle(Class target, Class source, SEL original, SEL replacement)
{
  Method originalMethod = class_getInstanceMethod(target, original);
  Method replacementMethod = class_getInstanceMethod(source, replacement);
  if (originalMethod == NULL || replacementMethod == NULL)
    {
      NSLog(@"Eau: %@ has no %@; drawers keep the libs-gui behaviour",
            NSStringFromClass(target), NSStringFromSelector(original));
      return;
    }
  class_addMethod(target, replacement, method_getImplementation(replacementMethod),
                  method_getTypeEncoding(replacementMethod));
  method_exchangeImplementations(originalMethod, class_getInstanceMethod(target, replacement));
}

+ (void) load
{
  Class cls = EAUDrawerWindowClass();
  if (cls == Nil)
    {
      return;
    }
  EAUDrawerSwizzle(cls, self, @selector(frameFromParentWindowFrameInState:),
                   @selector(eau_frameFromParentWindowFrameInState:));
  EAUDrawerSwizzle(cls, self, @selector(configureContainer:), @selector(eau_configureContainer:));
  EAUDrawerSwizzle(cls, self, @selector(slideOpen:onEdge:), @selector(eau_slideOpen:onEdge:));
  EAUDrawerSwizzle([NSDrawer class], [EauDrawerSwizzles class],
                   @selector(setContentSize:), @selector(eau_setContentSize:));
  EAUDrawerSwizzle([NSDrawer class], [EauDrawerSwizzles class],
                   @selector(setContentView:), @selector(eau_setContentView:));
}

/* libs-gui sizes the drawer from its maximum content size, unlimited by
 * default, which makes it as wide as a window can be, and parks a closed drawer
 * as a 16 px strip inside the parent.  The drawer is always given its open
 * frame: the window manager hides it under the parent while it is closed. */
- (NSRect) eau_frameFromParentWindowFrameInState: (NSInteger)state
{
  NSWindow *drawerWindow = (NSWindow *)self;
  NSWindow *parent = [drawerWindow parentWindow];
  NSDrawer *drawer = [drawerWindow drawer];
  NSRect parentFrame;

  if (!EauThemeIsActive() || parent == nil || drawer == nil)
    {
      return [self eau_frameFromParentWindowFrameInState: state];
    }
  parentFrame = [parent frame];
  return [EauDrawerGeometry frameForEdge: [drawer edge]
                             parentFrame: parentFrame
                           parentContent: [parent contentRectForFrameRect: parentFrame]
                             contentSize: EAUContentSizeOfDrawer(drawer)
                                 leading: [drawer leadingOffset]
                                trailing: [drawer trailingOffset]
                                  margin: METRICS_DRAWER_MARGIN];
}

/* The container box is inset by the drawer margin and draws nothing itself:
 * the surface is the drawer window's background. */
- (void) eau_configureContainer: (NSRect)contentRect
{
  NSWindow *drawerWindow = (NSWindow *)self;
  NSBox *box;

  [self eau_configureContainer: contentRect];
  if (!EauThemeIsActive())
    {
      return;
    }
  box = [drawerWindow container];
  /* A transparent custom box fills with the clear colour, so the drawer's
   * surface shows through; any other box fills with the window colour. */
  [box setBoxType: NSBoxCustom];
  [box setTransparent: YES];
  [box setBorderType: NSNoBorder];
  [box setContentViewMargins: NSZeroSize];
  [box setFrame: [EauDrawerGeometry contentRectForBounds: [[drawerWindow contentView] bounds]
                                                  margin: METRICS_DRAWER_MARGIN]];
}

/* libs-gui slides by resizing the window in ten blocking steps, the
 * opening ones before the window is even shown, so it popped in and
 * shrank out.  The window manager slides the finished drawer out from
 * under the parent and back instead; the window only needs its open frame. */
- (void) eau_slideOpen: (BOOL)opening onEdge: (NSRectEdge)edge
{
  NSWindow *drawerWindow = (NSWindow *)self;

  if (!EauThemeIsActive())
    {
      [self eau_slideOpen: opening onEdge: edge];
      return;
    }
  if (opening)
    {
      [drawerWindow setFrame: [drawerWindow frameFromParentWindowFrameInState: NSDrawerOpenState]
                     display: YES];
    }
}

@end
