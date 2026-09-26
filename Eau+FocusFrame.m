#import "Eau.h"
#import "Eau+Drawings.h"
#import "Eau+Stepper.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Behaviors/GBThemeHooks+FocusRing.h"

/* Whether the focus ring is currently allowed to show.  The policy (rings
 * only after Tab, hidden again by the mouse) belongs to GershwinBehaviors,
 * which reports every change through -gbKeyboardFocusVisibilityChanged:inWindow:;
 * this only mirrors it for drawing. */
static BOOL eauKeyboardFocusVisible = NO;

/* A transparent view pinned on top of the window's content view.  Drawing the
 * focus ring here (instead of inside the focused control) means it is never
 * clipped to the control's cell-frame bounds, it sits on top of neighbouring
 * widgets, and it can be traced just outside the control so it composites. */
@interface EauFocusOverlay : NSView
@property (nonatomic, retain) NSBezierPath *ringPath;
@property (nonatomic, assign) NSView *focusedView;
@end

@implementation EauFocusOverlay
- (BOOL) isOpaque
{
  return NO;
}
/* The overlay is pinned on top of the whole content view so the ring can sit
 * outside the focused widget and over its neighbours.  A plain NSView accepts
 * hit-testing, so without this every mouse event would land on the overlay and
 * never reach the button beneath it - the dialog's OK button would do nothing.
 * Returning nil makes the overlay fully transparent to the event system so
 * clicks and tracking fall through to the real controls. */
- (NSView *) hitTest: (NSPoint)aPoint
{
  return nil;
}
- (void) drawRect: (NSRect) rect
{
  if (_ringPath == nil)
    return;
  /* The ring is only valid while its control is still the first responder;
   * drop it the moment focus moves elsewhere. */
  if ([[self window] firstResponder] != _focusedView)
    {
      _ringPath = nil;
      return;
    }
  NSColor *src = [NSColor selectedControlColor];
  NSColor *rgb = [src colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  CGFloat r = (rgb != nil) ? [rgb redComponent] : 0.28;
  CGFloat g = (rgb != nil) ? [rgb greenComponent] : 0.58;
  CGFloat b = (rgb != nil) ? [rgb blueComponent] : 0.90;
  [[NSColor colorWithCalibratedRed: r green: g blue: b alpha: 1.0] setStroke];
  /* The path is traced 2px outside the widget (GNUstep only composites this
   * overlay's stroke when it stays in the margin, off the opaque face).  A 4px
   * stroke then spans [outline, outline+4]: its inner edge sits exactly on the
   * widget outline (flush, no gap) while its outer edge lands on top of
   * neighbours. */
  [_ringPath setLineWidth: 4];
  [_ringPath stroke];
}
@end

static const void *EauFocusOverlayKey = &EauFocusOverlayKey;

/* Clear any ring already painted for a window (used when navigation leaves
 * keyboard mode) and drop the overlay's cached path so it stops compositing.
 * Defined after EauFocusOverlay so the class and its associated-object key are
 * in scope. */
static void eauHideFocusRing(NSWindow *win)
{
  if (win == nil)
    return;
  EauFocusOverlay *ov = objc_getAssociatedObject(win, EauFocusOverlayKey);
  if (ov != nil && [ov ringPath] != nil)
    {
      NSRect old = [[ov ringPath] bounds];
      [ov setRingPath: nil];
      [ov setNeedsDisplayInRect: NSInsetRect(old, -6, -6)];
    }
}

static EauFocusOverlay *eauOverlayForWindow(NSWindow *win)
{
  EauFocusOverlay *ov = objc_getAssociatedObject(win, EauFocusOverlayKey);
  if (ov == nil)
    {
      ov = [[EauFocusOverlay alloc] initWithFrame: NSZeroRect];
      [ov setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      objc_setAssociatedObject(win, EauFocusOverlayKey, ov,
                               OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  return ov;
}

@implementation Eau (EauFocusFrame)

- (void) drawFocusFrame: (NSRect) frame view: (NSView*) view
{
  /* Keyboard navigation not active yet (window just opened, or the user is
   * using the mouse): do not paint a focus ring, so nothing is outlined until
   * Tab is pressed.  Also clear any ring left over from a previous keyboard
   * session so it does not linger after the user clicks away. */
  /* Without GershwinBehaviors nobody would ever turn the flag on, so fall
   * back to stock GNUstep and always draw the ring. */
  if (!eauKeyboardFocusVisible && NSClassFromString(@"GBBehaviors") != Nil)
    {
      eauHideFocusRing([view window]);
      return;
    }
  NSBezierPath * path;
  /* Trace the ring 2px outside the control's outline ([view bounds] / selected
   * cell frame).  drawFocusFrame is handed the cell interior (a few px inset),
   * which would sit on the opaque face and not composite, so we use the view's
   * own bounds, where the face is drawn. */
  CGFloat m = 2.0;
  NSRect base;
  if([view class] == [NSMatrix class])
    {
      NSUInteger row = [(NSMatrix*)view selectedRow];
      NSUInteger col = [(NSMatrix*)view selectedColumn];
      base = [(NSMatrix*) view cellFrameAtRow:row column: col];
    }
  else
    {
      base = [view bounds];
    }
  NSRect fr = NSInsetRect(base, -m, -m);

  if([view class] == [NSButton class])
    {
        NSButton *focusButton = (NSButton*)view;
        int bezel_style = [focusButton bezelStyle];
        switch (bezel_style)
          {
            case NSTexturedSquareBezelStyle:
            case NSSmallSquareBezelStyle:
            case NSRegularSquareBezelStyle:
            case NSShadowlessSquareBezelStyle:
            case NSThickSquareBezelStyle:
            case NSThickerSquareBezelStyle:
              path = [NSBezierPath bezierPathWithRect: fr];
              break;
            default:
              {
                CGFloat r = [self _eau_radiusForFrame: base];
                CGFloat leftR = r, rightR = r;
                [self _eau_adjacencyRadiiForView: view
                                      baseRadius: r
                                       leftRadius: &leftR
                                      rightRadius: &rightR];
                path = [self _eau_roundedPath: fr
                                       topLeft: leftR
                                      topRight: rightR
                                    bottomLeft: leftR
                                   bottomRight: rightR];
              }
              break;
          }
    }
  else if([view class] == [NSStepper class])
    {
      path = [self stepperBezierPathWithFrame: fr];
    }
  else if([view class] == [NSPopUpButton class])
    {
      path = [NSBezierPath bezierPathWithRoundedRect: fr xRadius: 3 yRadius: 3];
    }
  else if([view class] == [NSMatrix class])
    {
      path = [NSBezierPath bezierPathWithRoundedRect: fr xRadius: 3 yRadius: 3];
    }
  else
    {
      path = [NSBezierPath bezierPathWithRect: fr];
    }

  NSWindow *win = [view window];
  NSView *cv = [win contentView];
  if (cv == nil)
    return;
  NSRect vr = [view convertRect: base toView: cv];
  NSBezierPath *ring = [path copy];
  NSAffineTransform *t = [NSAffineTransform transform];
  [t translateXBy: vr.origin.x yBy: vr.origin.y];
  [ring transformUsingAffineTransform: t];

  EauFocusOverlay *ov = eauOverlayForWindow(win);
  /* Only repaint the overlay where the ring actually lives.  Marking the whole
   * overlay dirty (the old setNeedsDisplay: YES) forced a full-window composite
   * on every call - and drawFocusFrame runs on every redraw of the focused
   * control, including each frame of the pulsing default button - which starved
   * the run loop and made dialogs feel sluggish.  Confine the dirty rect to the
   * old and new ring bounds so the rest of the window is never touched. */
  NSRect oldBounds = NSZeroRect;
  if ([ov ringPath] != nil)
    oldBounds = [[ov ringPath] bounds];
  NSRect newBounds = [ring bounds];
  /* Skip the rest when the ring is unchanged: the pulsing default button
   * redraws every animation frame, but its focus ring geometry is identical, so
   * there is nothing new to paint.  This keeps the per-frame cost near zero. */
  if ([ov ringPath] != nil && [ov focusedView] == view
      && NSEqualRects(oldBounds, newBounds))
    {
      return;
    }
  [ov setRingPath: ring];
  [ov setFocusedView: view];
  [ov setFrame: [cv bounds]];
  /* Attach synchronously, guarded to once, to the live content view so the
   * overlay is actually in the window's view tree (a deferred add left it
   * detached, with [self window] nil, so it never composited). */
  if ([ov superview] != cv)
    {
      [cv addSubview: ov];
    }
  /* Expand by the stroke width (4) plus the 2px margin so the outline is fully
   * covered, then dirty both old and new ring rects to clear the previous trace. */
  NSRect dirty = NSUnionRect(oldBounds, newBounds);
  dirty = NSInsetRect(dirty, -6, -6);
  [ov setNeedsDisplayInRect: dirty];
}

- (void) gbKeyboardFocusVisibilityChanged: (BOOL)visible inWindow: (NSWindow *)window
{
  eauKeyboardFocusVisible = visible;
  /* A mouse click drops keyboard navigation: clear the ring already painted,
   * because the control will not redraw on its own to remove it. */
  if (!visible)
    {
      eauHideFocusRing(window);
    }
}

- (NSSize) sizeForBorderType: (NSBorderType) aType
{
  switch (aType)
    {
      case NSLineBorder:
        return NSMakeSize(4, 4);
      case NSGrooveBorder:
      case NSBezelBorder:
        return NSMakeSize(1, 1);
      case NSNoBorder:
      default:
        return NSZeroSize;
    }
}

@end
