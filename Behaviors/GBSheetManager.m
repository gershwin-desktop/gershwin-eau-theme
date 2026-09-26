/* GBSheetManager.m - window-modal sheet sessions
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - NSApplication/NSWindow should run sheets as
 * window-modal sessions (return at once, block only the parent) instead of
 * -runModalForWindow:relativeToWindow:.
 *
 * libs-gui runs every sheet as an app-modal -runModalForWindow: centered on
 * the parent.  Here a sheet is a borderless child window pinned under the
 * parent's titlebar; the parent refuses input while it is attached (see
 * NSWindow+GBSheet.m) and the rest of the app keeps running normally.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <GNUstepGUI/GSTheme.h>
#import <GNUstepGUI/GSWindowDecorationView.h>

#import "GBSheet.h"
#import "GBTheme.h"
#import "GBThemeHooks+Sheet.h"

/* libs-gui internals used to re-dress a live window. */
@interface NSView (GBSheetPrivate)
- (void)_viewWillMoveToWindow:(NSWindow *)newWindow;
@end

@interface NSWindow (GBSheetPrivate)
- (void)_initBackendWindow;
- (void)setAttachedSheet:(id)sheet;
@end

@interface NSWindow (GBSheetStyle)
- (NSRect)gb_sheetSetStyleMask:(NSUInteger)mask;
@end

@interface GBSheetSession : NSObject {
@public
  NSWindow *sheet;
  NSWindow *parent;
  id owner;
  id delegate;
  SEL didEnd;
  void *contextInfo;
  GSNSWindowDidEndSheetCallbackBlock handler;
  NSInteger returnCode;
  BOOL active;
  NSUInteger savedStyleMask;
  NSInteger savedLevel;
  BOOL savedHidesOnDeactivate;
  NSSize fullSize;
  NSTimer *animationTimer;
  NSDate *animationStart;
  NSTimeInterval animationDuration;
  NSSize savedMinSize;
  BOOL savedAutoresizes;
}
@end

@implementation GBSheetSession
@end

@interface GBSheetManager : NSObject
+ (GBSheetManager *)sharedManager;
- (void)observeParent:(NSWindow *)parent;
- (void)forgetParent:(NSWindow *)parent;
- (void)finishSession:(GBSheetSession *)session;
- (void)animationTick:(NSTimer *)timer;
@end

/* Active and queued sessions, oldest first.  Only a handful exist at a
 * time, so linear lookups are fine. */
static NSMutableArray *sSessions = nil;

static id sNextOwner = nil;

void GBSheetSetNextOwner(id owner)
{
  sNextOwner = owner;
}

static NSArray *GBSheetRunLoopModes(void)
{
  /* Callbacks must also fire while a menu is tracked or an app-modal panel
   * runs, or a sheet ended from there would never report back. */
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                   NSEventTrackingRunLoopMode, nil];
}

BOOL GBSheetsEnabled(void)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey:GBWindowModalSheetsDefault];

  return (value == nil) ? YES : [value boolValue];
}

static GBSheetSession *GBSessionForSheet(NSWindow *sheet)
{
  for (GBSheetSession *s in sSessions) {
    if (s->sheet == sheet) {
      return s;
    }
  }
  return nil;
}

static GBSheetSession *GBActiveSessionForParent(NSWindow *parent)
{
  for (GBSheetSession *s in sSessions) {
    if (s->active && s->parent == parent) {
      return s;
    }
  }
  return nil;
}

BOOL GBSheetIsManaged(NSWindow *sheet)
{
  return sheet != nil && GBSessionForSheet(sheet) != nil;
}

BOOL GBSheetIsActive(NSWindow *sheet)
{
  GBSheetSession *s = (sheet != nil) ? GBSessionForSheet(sheet) : nil;

  return s != nil && s->active;
}

NSWindow *GBSheetParentOf(NSWindow *sheet)
{
  GBSheetSession *s = (sheet != nil) ? GBSessionForSheet(sheet) : nil;

  return (s != nil) ? s->parent : nil;
}

NSWindow *GBSheetActiveSheetOf(NSWindow *parent)
{
  GBSheetSession *s;

  if (parent == nil || [sSessions count] == 0) {
    return nil;
  }
  s = GBActiveSessionForParent(parent);
  return (s != nil) ? s->sheet : nil;
}

NSArray *GBSheetSheetsOf(NSWindow *parent)
{
  NSMutableArray *result = [NSMutableArray array];

  for (GBSheetSession *s in sSessions) {
    if (s->parent == parent) {
      [result addObject:s->sheet];
    }
  }
  return result;
}

static NSWindow *GBRootParent(NSWindow *sheet)
{
  NSWindow *root = sheet;
  NSWindow *up;
  NSUInteger guard = 0;

  while ((up = GBSheetParentOf(root)) != nil && guard++ < 16) {
    root = up;
  }
  return root;
}

BOOL GBSheetWorksWhenModal(NSWindow *sheet)
{
  NSWindow *modal = [NSApp modalWindow];

  return modal != nil && GBSheetIsActive(sheet) && GBRootParent(sheet) == modal;
}

NSWindow *GBSheetTargetForStopModal(void)
{
  NSWindow *modal;
  NSWindow *candidate = nil;

  if ([sSessions count] == 0) {
    return nil;
  }
  modal = [NSApp modalWindow];
  if (GBSheetIsActive([NSApp keyWindow])) {
    candidate = [NSApp keyWindow];
  }
  else if (modal == nil) {
    /* The key window can be elsewhere when a panel is ended from a timer
     * or with the app inactive; the newest sheet is the best guess. */
    for (GBSheetSession *s in [sSessions reverseObjectEnumerator]) {
      if (s->active) {
        candidate = s->sheet;
        break;
      }
    }
  }
  if (candidate == nil) {
    return nil;
  }
  /* A running app-modal session wins unless the sheet hangs off its window:
   * then the stop can only have come from the sheet, the parent is blocked. */
  if (modal != nil && modal != GBRootParent(candidate)) {
    return nil;
  }
  return candidate;
}

/* Just below the parent's titlebar (and toolbar), centered horizontally. */
static NSRect GBSheetTargetFrame(GBSheetSession *s)
{
  NSRect parentFrame = [s->parent frame];
  NSView *content = [s->parent contentView];
  CGFloat top;
  NSRect frame;

  if (content != nil) {
    top = NSMinY(parentFrame) + NSMaxY([content frame]);
  }
  else {
    top = NSMaxY([s->parent contentRectForFrameRect:parentFrame]);
  }
  frame.size = s->fullSize;
  frame.origin.x = NSMinX(parentFrame) + floor((NSWidth(parentFrame) - frame.size.width) / 2.0);
  frame.origin.y = top - frame.size.height;
  return frame;
}

static void GBSheetStopAnimation(GBSheetSession *s)
{
  if (s->animationTimer == nil) {
    return;
  }
  [s->animationTimer invalidate];
  s->animationTimer = nil;
  s->animationStart = nil;
  [[s->sheet contentView] setAutoresizesSubviews:s->savedAutoresizes];
  [s->sheet setMinSize:s->savedMinSize];
  [s->sheet setFrame:GBSheetTargetFrame(s) display:YES];
}

void GBSheetPlace(NSWindow *sheet)
{
  GBSheetSession *s = GBSessionForSheet(sheet);

  /* A running animation re-reads the target frame on every tick. */
  if (s == nil || s->active == NO || s->animationTimer != nil) {
    return;
  }
  [sheet setFrame:GBSheetTargetFrame(s) display:YES];
}

static BOOL GBSheetMayAnimate(NSWindow *sheet)
{
  id delegate = [sheet delegate];

  /* The slide resizes the window; delegates that lay out on resize would
   * see a transient tiny window, so those sheets simply appear. */
  if ([delegate respondsToSelector:@selector(windowDidResize:)] ||
      [delegate respondsToSelector:@selector(windowWillResize:toSize:)]) {
    return NO;
  }
  return [sheet contentView] != nil;
}

static void GBSheetShow(GBSheetSession *s)
{
  NSWindow *sheet = s->sheet;
  NSWindow *parent = s->parent;
  NSRect target;
  id theme;

  s->active = YES;
  [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillBeginSheetNotification
                                                      object:parent];

  GBSheetPrepareClass(object_getClass(sheet));
  s->savedStyleMask = [sheet styleMask];
  s->savedLevel = [sheet level];
  s->savedHidesOnDeactivate = [sheet hidesOnDeactivate];

  s->fullSize = [sheet gb_sheetSetStyleMask:NSBorderlessWindowMask].size;
  /* A sheet belongs to its parent: same level, and it must not vanish on
   * app deactivation while the parent stays visible and blocked. */
  [sheet setHidesOnDeactivate:NO];
  [sheet setLevel:[parent level]];
  [sheet setParentWindow:parent];
  if ([parent respondsToSelector:@selector(setAttachedSheet:)]) {
    [parent setAttachedSheet:sheet];
  }

  /* The WM hints must be on the X window before it is mapped. */
  if ([sheet windowNumber] == 0 && [sheet respondsToSelector:@selector(_initBackendWindow)]) {
    [sheet _initBackendWindow];
  }
  GBSheetX11Attach(sheet, parent);
  [[GBSheetManager sharedManager] observeParent:parent];

  target = GBSheetTargetFrame(s);
  theme = GBThemeIfResponds(@selector(sheetAnimationDurationForWindow:));
  s->animationDuration = (theme != nil) ? [theme sheetAnimationDurationForWindow:sheet] : 0.0;
  if (s->animationDuration > 0.0 && GBSheetMayAnimate(sheet)) {
    NSRect start = target;

    /* Shrinking the window with a non-autoresizing content view clips
     * the sheet from the top, so its bottom edge appears first right
     * under the titlebar - the sheet seems to slide out from under it. */
    s->savedAutoresizes = [[sheet contentView] autoresizesSubviews];
    s->savedMinSize = [sheet minSize];
    [[sheet contentView] setAutoresizesSubviews:NO];
    [sheet setMinSize:NSMakeSize(1, 1)];
    start.size.height = 1;
    start.origin.y = NSMaxY(target) - 1;
    [sheet setFrame:start display:NO];
    s->animationStart = [NSDate date];
    s->animationTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0
                                                target:[GBSheetManager sharedManager]
                                              selector:@selector(animationTick:)
                                              userInfo:s
                                               repeats:YES];
    for (NSString *mode in GBSheetRunLoopModes()) {
      [[NSRunLoop currentRunLoop] addTimer:s->animationTimer forMode:mode];
    }
  }
  else {
    [sheet setFrame:target display:NO];
  }

  [sheet orderWindow:NSWindowAbove relativeTo:[parent windowNumber]];
  if ([NSApp isActive] && [parent isMiniaturized] == NO) {
    [sheet makeKeyWindow];
  }
}

static void GBSheetShowNext(NSWindow *parent)
{
  if (parent == nil || GBActiveSessionForParent(parent) != nil) {
    return;
  }
  for (GBSheetSession *s in sSessions) {
    if (s->parent == parent) {
      GBSheetShow(s);
      return;
    }
  }
  [[GBSheetManager sharedManager] forgetParent:parent];
}

void GBSheetBegin(NSWindow *sheet, NSWindow *parent, id delegate, SEL didEnd, void *contextInfo,
                  GSNSWindowDidEndSheetCallbackBlock handler, BOOL critical)
{
  GBSheetSession *s;
  NSUInteger index;

  if (sSessions == nil) {
    sSessions = [NSMutableArray new];
  }
  if (GBSessionForSheet(sheet) != nil) {
    NSLog(@"GershwinBehaviors: %@ is already a sheet, ignoring beginSheet", sheet);
    return;
  }

  s = [GBSheetSession new];
  s->sheet = sheet;
  s->parent = parent;
  s->owner = sNextOwner;
  sNextOwner = nil;
  s->delegate = delegate;
  s->didEnd = didEnd;
  s->contextInfo = contextInfo;
  s->handler = [handler copy];
  s->returnCode = NSRunStoppedResponse;

  /* One sheet per window: later ones wait.  A critical sheet goes first
   * in that queue. */
  index = [sSessions count];
  if (critical) {
    NSUInteger i;
    for (i = 0; i < [sSessions count]; i++) {
      GBSheetSession *other = [sSessions objectAtIndex:i];
      if (other->parent == parent && other->active == NO) {
        index = i;
        break;
      }
    }
  }
  [sSessions insertObject:s atIndex:index];

  if (GBActiveSessionForParent(parent) == nil) {
    GBSheetShow(s);
  }
}

BOOL GBSheetEnd(NSWindow *sheet, NSInteger returnCode)
{
  GBSheetSession *s = GBSessionForSheet(sheet);
  NSWindow *parent;

  if (s == nil) {
    return NO;
  }
  parent = s->parent;
  s->returnCode = returnCode;

  if (s->active) {
    BOOL wasKey = [sheet isKeyWindow];

    GBSheetStopAnimation(s);
    s->active = NO;
    [sheet orderOut:nil];
    GBSheetX11Detach(sheet);
    [sheet setParentWindow:nil];
    if ([parent respondsToSelector:@selector(setAttachedSheet:)]) {
      [parent setAttachedSheet:nil];
    }
    [sheet gb_sheetSetStyleMask:s->savedStyleMask];
    [sheet setLevel:s->savedLevel];
    [sheet setHidesOnDeactivate:s->savedHidesOnDeactivate];
    [sSessions removeObjectIdenticalTo:s];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowDidEndSheetNotification
                                                        object:parent];
    if ((wasKey || [NSApp keyWindow] == nil) && [parent isVisible] &&
        [parent isMiniaturized] == NO) {
      [parent makeKeyWindow];
    }
  }
  else {
    [sSessions removeObjectIdenticalTo:s];
  }

  /* Cocoa reports the end from the event loop, after endSheet: returned,
   * so callers may still tidy up the sheet before their callback runs. */
  [[GBSheetManager sharedManager] performSelector:@selector(finishSession:)
                                       withObject:s
                                       afterDelay:0.0
                                          inModes:GBSheetRunLoopModes()];
  return YES;
}

@implementation GBSheetManager

+ (GBSheetManager *)sharedManager
{
  static GBSheetManager *manager = nil;

  if (manager == nil) {
    manager = [GBSheetManager new];
  }
  return manager;
}

- (void)observeParent:(NSWindow *)parent
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  /* Removing first keeps one registration per parent however many sheets
   * it had queued. */
  [self forgetParent:parent];
  [nc addObserver:self
         selector:@selector(parentDidChangeFrame:)
             name:NSWindowDidMoveNotification
           object:parent];
  [nc addObserver:self
         selector:@selector(parentDidChangeFrame:)
             name:NSWindowDidResizeNotification
           object:parent];
  [nc addObserver:self
         selector:@selector(parentWillClose:)
             name:NSWindowWillCloseNotification
           object:parent];
  [nc addObserver:self
         selector:@selector(parentDidMiniaturize:)
             name:NSWindowDidMiniaturizeNotification
           object:parent];
  [nc addObserver:self
         selector:@selector(parentDidDeminiaturize:)
             name:NSWindowDidDeminiaturizeNotification
           object:parent];
}

- (void)forgetParent:(NSWindow *)parent
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  [nc removeObserver:self name:NSWindowDidMoveNotification object:parent];
  [nc removeObserver:self name:NSWindowDidResizeNotification object:parent];
  [nc removeObserver:self name:NSWindowWillCloseNotification object:parent];
  [nc removeObserver:self name:NSWindowDidMiniaturizeNotification object:parent];
  [nc removeObserver:self name:NSWindowDidDeminiaturizeNotification object:parent];
}

- (void)parentDidChangeFrame:(NSNotification *)note
{
  GBSheetPlace(GBSheetActiveSheetOf([note object]));
}

- (void)parentWillClose:(NSNotification *)note
{
  NSWindow *parent = [note object];
  NSArray *sheets = GBSheetSheetsOf(parent);

  /* Closing is refused while a sheet is up, so this is a programmatic
   * -close: do not leave an orphaned sheet (and its session) behind. */
  for (NSWindow *sheet in [sheets reverseObjectEnumerator]) {
    GBSheetEnd(sheet, NSRunAbortedResponse);
  }
  [self forgetParent:parent];
}

- (void)parentDidMiniaturize:(NSNotification *)note
{
  [GBSheetActiveSheetOf([note object]) orderOut:nil];
}

- (void)parentDidDeminiaturize:(NSNotification *)note
{
  NSWindow *parent = [note object];
  NSWindow *sheet = GBSheetActiveSheetOf(parent);

  if (sheet != nil) {
    GBSheetPlace(sheet);
    [sheet orderWindow:NSWindowAbove relativeTo:[parent windowNumber]];
    [sheet makeKeyWindow];
  }
}

- (void)animationTick:(NSTimer *)timer
{
  GBSheetSession *s = [timer userInfo];
  NSRect target;
  NSRect frame;
  double t;

  if (s->animationTimer != timer || s->active == NO) {
    [timer invalidate];
    return;
  }
  t = -[s->animationStart timeIntervalSinceNow] / s->animationDuration;
  if (t >= 1.0) {
    GBSheetStopAnimation(s);
    return;
  }
  /* Ease out: fast start, gentle landing. */
  t = 1.0 - (1.0 - t) * (1.0 - t);
  target = GBSheetTargetFrame(s);
  frame = target;
  frame.size.height = MAX(1.0, floor(NSHeight(target) * t));
  frame.origin.y = NSMaxY(target) - frame.size.height;
  [s->sheet setFrame:frame display:YES];
}

- (void)finishSession:(GBSheetSession *)s
{
  NSWindow *parent = s->parent;
  GSNSWindowDidEndSheetCallbackBlock handler = s->handler;
  id delegate = s->delegate;

  s->handler = nil;
  s->delegate = nil;
  if (handler != nil) {
    handler(s->returnCode);
  }
  else if (delegate != nil && s->didEnd != NULL && [delegate respondsToSelector:s->didEnd]) {
    void (*didEnd)(id, SEL, id, NSInteger, void *);

    didEnd = (void (*)(id, SEL, id, NSInteger, void *))[delegate methodForSelector:s->didEnd];
    didEnd(delegate, s->didEnd, s->sheet, s->returnCode, s->contextInfo);
  }
  s->owner = nil;
  GBSheetShowNext(parent);
}

@end

@implementation NSWindow (GBSheetStyle)

/* libs-gui has no -setStyleMask:, and the decoration view caches what the
 * style mask implies (titlebar, buttons, content offsets), so the window
 * gets a fresh decoration view for the new mask; content view, first
 * responder and backend window are kept.  Returns the new frame, keeping
 * the content rect where it was.
 * TODO: Upstream to GNUstep - add -[NSWindow setStyleMask:] rebuilding the
 * decoration view, so sheets can drop their titlebar without this. */
- (NSRect)gb_sheetSetStyleMask:(NSUInteger)mask
{
  NSView *content = [self contentView];
  NSResponder *responder = [self firstResponder];
  NSColor *background = [self backgroundColor];
  NSRect oldFrame;
  NSRect contentRect;
  NSRect frame;
  GSWindowDecorationView *decoration;
  NSUInteger oldMask = _styleMask;
  int num = (int)[self windowNumber];

  if (mask == _styleMask) {
    return [self frame];
  }

  oldFrame = [self frame];
  contentRect = [self contentRectForFrameRect:oldFrame];
  _styleMask = mask;
  frame = [self frameRectForContentRect:contentRect];
  decoration = [[GSWindowDecorationView windowDecorator]
      newWindowDecorationViewWithFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))
                                window:self];
  if (decoration == nil) {
    _styleMask = oldMask;
    return [self frame];
  }

  /* Removing the content view makes the old decoration view clear the
   * window's (unretained) content view pointer; setContentView: below
   * then installs it in the new one. */
  [content removeFromSuperview];
  _wv = decoration;
  [_wv _viewWillMoveToWindow:self];
  [_wv setNextResponder:self];
  if (content != nil) {
    [self setContentView:content];
  }
  [_wv setBackgroundColor:background];
  [_wv setTitle:[self title]];
  [_wv setDocumentEdited:[self isDocumentEdited]];

  if (num != 0) {
    GSDisplayServer *srv = GSServerForWindow(self);

    if ([srv handlesWindowDecorations]) {
      [srv stylewindow:(unsigned int) mask:num];
    }
    [_wv setWindowNumber:num];
  }
  /* Size limits are frame sizes: a panel that pinned its size (alert
   * panels set min == max) would otherwise be forced back to its titled
   * height.  Shifting them by the frame change keeps the same content
   * limits and undoes itself when the old mask comes back. */
  {
    CGFloat dw = NSWidth(frame) - NSWidth(oldFrame);
    CGFloat dh = NSHeight(frame) - NSHeight(oldFrame);
    NSSize minSize = [self minSize];
    NSSize maxSize = [self maxSize];

    minSize.width = MAX(1.0, minSize.width + dw);
    minSize.height = MAX(1.0, minSize.height + dh);
    maxSize.width = MAX(minSize.width, maxSize.width + dw);
    maxSize.height = MAX(minSize.height, maxSize.height + dh);
    [self setMinSize:minSize];
    [self setMaxSize:maxSize];
  }
  [self setFrame:frame display:NO];

  if ([responder isKindOfClass:[NSView class]] && [(NSView *)responder window] == self) {
    [self makeFirstResponder:responder];
  }
  [_wv setNeedsDisplay:YES];
  return frame;
}

@end
