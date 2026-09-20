#include "Eau+Button.h"
#include "EauWindowButton.h"
#include "EauTitleBarButton.h"
#include "Eau+TitleBarButtons.h"
#include "EauGrowBoxView.h"
#include "AppearanceMetrics.h"
#import <AppKit/NSWindow.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSAlert.h>
#import "GNUstepGUI/GSTheme.h"
#import <objc/runtime.h>

// Dialog logging helpers (used by NSWindow presentation hooks).
static BOOL EAUIsDialogWindow(NSWindow *window)
{
  if (window == nil)
    {
      return NO;
    }
  if ([window isKindOfClass: [NSPanel class]])
    {
      return YES;
    }
  if ([window level] >= NSModalPanelWindowLevel)
    {
      return YES;
    }
  if (([window styleMask] & NSUtilityWindowMask) != 0)
    {
      return YES;
    }
  return NO;
}

static void EAUCollectDialogTextFromView(NSMutableArray *parts, NSView *view)
{
  if (view == nil || parts == nil)
    {
      return;
    }
    
  @try {
    if ([view isKindOfClass: [NSTextField class]])
      {
        NSTextField *field = (NSTextField *)view;
        NSString *value = [field stringValue];
        if (value != nil && [value length] > 0)
          {
            [parts addObject: value];
          }
      }
    
    // Check if subviews array exists and is valid
    NSArray *subviews = nil;
    @try {
      subviews = [view subviews];
    } @catch (id ex) {}
    
    if (subviews) {
      NSUInteger count = [subviews count];
      for (NSUInteger i = 0; i < count; i++)
        {
          @try {
            EAUCollectDialogTextFromView(parts, [subviews objectAtIndex: i]);
          } @catch (id ex) {}
        }
    }
  } @catch (NSException *e) {
    // Silently ignore errors during view traversal (e.g. during dealloc)
  }
}

static NSString *EAUDialogTextSummary(NSWindow *window)
{
  NSMutableArray *parts = [NSMutableArray array];
  NSString *title = [window title];
  if (title != nil && [title length] > 0)
    {
      [parts addObject: title];
    }
  EAUCollectDialogTextFromView(parts, [window contentView]);
  if ([parts count] == 0)
    {
      return @"";
    }
  return [parts componentsJoinedByString: @" | "];
}

static void EAUWindowLog(NSString *event, NSWindow *window)
{
  if (window == nil)
    {
      NSDebugLog(@"EauWindowLog: %@ window=(null)", event);
      return;
    }
  NSString *summary = nil;
  if (EAUIsDialogWindow(window))
    {
      summary = EAUDialogTextSummary(window);
    }
  NSDebugLog(@"EauWindowLog: %@ window=%p class=%@ title='%@' visible=%d key=%d main=%d level=%ld",
         event,
         window,
         NSStringFromClass([window class]),
         [window title],
         (int)[window isVisible],
         (int)[window isKeyWindow],
         (int)[window isMainWindow],
         (long)[window level]);
  if (summary != nil && [summary length] > 0)
    {
      NSDebugLog(@"EauDialog: window=%p class=%@ text='%@'", window, NSStringFromClass([window class]), summary);
    }
}

@implementation NSWindow (EauLogging)

+ (void) load
{
  static BOOL swizzled = NO;
  if (swizzled)
    {
      return;
    }
  swizzled = YES;

  Class cls = [NSWindow class];
  Method orig;
  Method swiz;

  orig = class_getInstanceMethod(cls, @selector(orderFront:));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderFrontRegardless));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderFrontRegardless));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(makeKeyAndOrderFront:));
  swiz = class_getInstanceMethod(cls, @selector(eau_makeKeyAndOrderFront:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(orderOut:));
  swiz = class_getInstanceMethod(cls, @selector(eau_orderOut:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  orig = class_getInstanceMethod(cls, @selector(close));
  swiz = class_getInstanceMethod(cls, @selector(eau_close));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  /* windowWillReturnFieldEditor:toObject: swizzling REMOVED - it was causing crashes */

  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(eau_windowWillClose:)
                                               name: NSWindowWillCloseNotification
                                             object: nil];
}

+ (void) eau_windowWillClose: (NSNotification *)note
{
  NSWindow *window = (NSWindow *)[note object];
  EAUWindowLog(@"willClose", window);
}


- (void) eau_orderFront: (id)sender
{
  EAUWindowLog(@"orderFront", self);
  if (EauThemeIsActive()) [EauGrowBoxView addToWindow:self];
  [self eau_orderFront: sender];
}

- (void) eau_orderFrontRegardless
{
  EAUWindowLog(@"orderFrontRegardless", self);
  if (EauThemeIsActive()) [EauGrowBoxView addToWindow:self];
  [self eau_orderFrontRegardless];
}

- (void) eau_makeKeyAndOrderFront: (id)sender
{
  EAUWindowLog(@"makeKeyAndOrderFront", self);
  if (EauThemeIsActive()) [EauGrowBoxView addToWindow:self];
  [self eau_makeKeyAndOrderFront: sender];
}

- (void) eau_orderOut: (id)sender
{
  EAUWindowLog(@"orderOut", self);
  [self eau_orderOut: sender];
}

- (void) eau_close
{
  EAUWindowLog(@"close", self);
  [self eau_close];
}

/* REMOVED: eau_windowWillReturnFieldEditor:toObject: swizzling.
   This delegate method should not be swizzled into NSWindow itself.
   The swizzle caused objc_msgSend_stret crashes due to incorrect type
   encoding. If GWDialog needs to customize field editor behavior, it
   should implement this as a proper delegate method on its delegate object,
   not swizzle it into the window class. */

@end

@interface DefaultButtonAnimationController : NSObject <NSWindowDelegate>

{
  NSTimer * pulseTimer;
  __weak NSButtonCell * buttoncell;
}

@property (nonatomic, weak) NSButtonCell * buttoncell;

- (void) startPulse;
- (void) stopPulse;
- (void) pulseTick;

@end

/* NSTimer retains its target.  The controller lives exactly as long as the
 * window's association keeps it, so the timer must not keep it alive as well:
 * this proxy holds the controller weakly and retires the timer once it is gone. */
@interface EauPulseTicker : NSObject
@property (nonatomic, weak) DefaultButtonAnimationController *controller;
@end

@implementation EauPulseTicker
@synthesize controller;
- (void) tick: (NSTimer *)timer
{
  DefaultButtonAnimationController *c = controller;

  if (c == nil)
    {
      [timer invalidate];
      return;
    }
  [c pulseTick];
}
@end

@implementation DefaultButtonAnimationController
@synthesize buttoncell;
- (id) initWithButtonCell: (NSButtonCell*) cell
{
  NSDebugLog(@"DefaultButtonAnimationController: initWithButtonCell called with cell %p", cell);
  if (self = [super init]) {
    self.buttoncell = cell;    NSDebugLog(@"DefaultButtonAnimationController: Initialized for button cell %p", cell);    
    // Register for additional window notifications to handle visibility changes
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowWillClose:) 
                                                 name:NSWindowWillCloseNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidMiniaturize:) 
                                                 name:NSWindowDidMiniaturizeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(windowDidDeminiaturize:) 
                                                 name:NSWindowDidDeminiaturizeNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResignKey:)
                                                 name:NSWindowDidResignKeyNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationDidHide:) 
                                                 name:NSApplicationDidHideNotification 
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(applicationDidUnhide:) 
                                                 name:NSApplicationDidUnhideNotification 
                                               object:nil];
    
    // Monitor for control state changes (enabled/disabled) using KVO
    if ([buttoncell controlView]) {
      NSControl *control = (NSControl *)[buttoncell controlView];
      @try {
        [control addObserver:self
                  forKeyPath:@"enabled"
                     options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                     context:NULL];
        NSDebugLog(@"DefaultButtonAnimationController: Added KVO observer for enabled property on control %p", control);
      }
      @catch (NSException *exception) {
        NSDebugLog(@"DefaultButtonAnimationController: ERROR adding KVO observer for enabled property: %@", exception);
      }
    }
    
    NSDebugLog(@"DefaultButtonAnimationController: Successfully initialized with cell %p", cell);
  }
  return self;
}

/* windowWillReturnFieldEditor:toObject:
 * NSWindowDelegate method that allows customizing the field editor for text input.
 * The field editor is a shared NSText object used for editing text in NSTextField
 * and other text controls.
 *
 * CRITICAL: This method MUST be implemented to avoid a crash on ARM64 architecture.
 * Without this implementation, the Objective-C runtime can incorrectly use
 * objc_msgSend_stret (structure-return calling convention) instead of objc_msgSend
 * (pointer-return calling convention), causing a SIGSEGV when the window tries to
 * get a field editor for text input.
 *
 * By explicitly implementing this method and returning nil, we:
 * 1. Prevent the objc_msgSend_stret crash
 * 2. Tell NSWindow to use its default field editor (which is correct behavior)
 * 3. Ensure text fields work properly with focus and keyboard input
 *
 * This is safe for GWDialog and other windows that use text fields.
 */
- (id)windowWillReturnFieldEditor:(id)fieldEditor toObject:(id)anObject
{
  NSDebugLog(@"DefaultButtonAnimationController: windowWillReturnFieldEditor called for object %p, returning nil (use default)", anObject);
  return nil;  // Return nil to use the default field editor
}


- (void) dealloc
{
  NSDebugLog(@"DefaultButtonAnimationController: dealloc called");
  
  @try {
    // Stop the pulse and remove all notifications
    [self stopPulse];
    
    // Use a local copy of buttoncell to avoid issues if it becomes nil during dealloc
    NSButtonCell *cell = buttoncell;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Remove KVO observer for enabled property safely
    // We only do this if we can still reach the control and it seems valid
    if (cell) {
      @try {
        NSView *cv = [cell controlView];
        if (cv && [cv isKindOfClass:[NSControl class]]) {
          NSControl *control = (NSControl *)cv;
          // paracoid check: only remove if it's still alive enough to have property
          [control removeObserver:self forKeyPath:@"enabled"];
          NSDebugLog(@"DefaultButtonAnimationController: Removed KVO observer for enabled property on control %p", control);
        }
      } @catch (NSException *exception) {
        NSDebugLog(@"DefaultButtonAnimationController: Exception removing KVO: %@", exception);
      }
      
      @try {
        [cell setIsDefaultButton: [NSNumber numberWithBool: NO]];
      } @catch (id ex) {}
    }
  } @catch (NSException *exception) {
    NSDebugLog(@"DefaultButtonAnimationController: ERROR in dealloc: %@", exception);
  }
  
  buttoncell = nil;
}

/* The pulse colour is derived from the wall clock when the cell is drawn
 * (-[Eau pulseColorInCell:]), so pulsing only needs the button to be redrawn
 * regularly.  A plain repeating timer does that; it is also scheduled in the
 * modal and event-tracking modes so the pulse keeps going inside alert panels
 * and while the user holds the mouse down elsewhere. */
- (void) startPulse
{
  NSDebugLog(@"DefaultButtonAnimationController: startPulse called for cell %p", buttoncell);

  if (pulseTimer != nil)
    {
      return;
    }

  /* The pulse is Eau's own default-button treatment; under another theme it
   * would only burn a timer per dialog and redraw a button that does not
   * pulse. */
  if (!EauThemeIsActive())
    {
      return;
    }

  // Check if the button cell is enabled before starting animation
  BOOL isEnabled = YES;
  if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
    isEnabled = [buttoncell isEnabled];
  }

  if (!isEnabled) {
    NSDebugLog(@"DefaultButtonAnimationController: Button cell is disabled, not starting animation");
    return;
  }

  EauPulseTicker *ticker = [[EauPulseTicker alloc] init];
  ticker.controller = self;
  pulseTimer = [NSTimer timerWithTimeInterval: 1.0 / METRICS_PULSE_FRAME_RATE
                                       target: ticker
                                     selector: @selector(tick:)
                                     userInfo: nil
                                      repeats: YES];

  NSRunLoop *loop = [NSRunLoop currentRunLoop];
  [loop addTimer: pulseTimer forMode: NSDefaultRunLoopMode];
  [loop addTimer: pulseTimer forMode: NSModalPanelRunLoopMode];
  [loop addTimer: pulseTimer forMode: NSEventTrackingRunLoopMode];
}

- (void) stopPulse
{
  [pulseTimer invalidate];
  pulseTimer = nil;
}

- (void) pulseTick
{
  NSButtonCell *cell = buttoncell;

  if (cell == nil || !EauThemeIsActive())
    {
      [self stopPulse];
      return;
    }

  /* -controlView stays nil until the cell's first draw; the first regular
   * window display fills it in and the pulse picks up from there. */
  [[cell controlView] setNeedsDisplay: YES];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
      NSDebugLog(@"DefaultButtonAnimationController: Window resigned key, stopping animation");
      [self stopPulse];
}

// TS: added this method
- (void)windowDidBecomeKey:(NSNotification *)notification
{
      NSWindow *window = [notification object];
      NSWindow *buttonWindow = [[buttoncell controlView] window];
      
      NSDebugLog(@"DefaultButtonAnimationController: Window became key notification received");
      NSDebugLog(@"DefaultButtonAnimationController: Notifying window %p, button window %p", window, buttonWindow);
      
      if (window == buttonWindow)
        {
          if ([self shouldAnimationBeRunning]) {
              NSDebugLog(@"DefaultButtonAnimationController: Button's window became key and button is enabled, starting animation");
              [self startPulse];
          } else {
              NSDebugLog(@"DefaultButtonAnimationController: Button's window became key but button is disabled, not starting animation");
          }
        }
      else
        {
          NSDebugLog(@"DefaultButtonAnimationController: Different window became key, ignoring");
        }
}

// Additional notification handlers for proper visibility management
- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *closingWindow = [notification object];
    NSWindow *buttonWindow = nil;
    
    @try {
        buttonWindow = [[buttoncell controlView] window];
    } @catch (id ex) {}
    
    if (closingWindow == buttonWindow || closingWindow == nil) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window is closing, stopping animation");
        [self stopPulse];
    }
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    NSWindow *miniaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (miniaturizedWindow == buttonWindow) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window was miniaturized, stopping animation");
        [self stopPulse];
    }
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    NSWindow *deminiaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (deminiaturizedWindow == buttonWindow && [self shouldAnimationBeRunning]) {
        NSDebugLog(@"DefaultButtonAnimationController: Button's window was deminiaturized and button is enabled, starting animation");
        [self startPulse];
    }
}

- (void)applicationDidHide:(NSNotification *)notification
{
    NSDebugLog(@"DefaultButtonAnimationController: Application was hidden, stopping animation");
    [self stopPulse];
}

- (void)applicationDidUnhide:(NSNotification *)notification
{
    if ([self shouldAnimationBeRunning]) {
        NSDebugLog(@"DefaultButtonAnimationController: Application was unhidden and button is enabled and visible, starting animation");
        [self startPulse];
    } else {
        NSDebugLog(@"DefaultButtonAnimationController: Application was unhidden but button is disabled or window not visible, not starting animation");
    }
}

// Helper method to check if animation should be running
- (BOOL)shouldAnimationBeRunning
{
    // Check if button cell is enabled
    BOOL isEnabled = YES;
    if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
        isEnabled = [buttoncell isEnabled];
    }
    
    if (!isEnabled) {
        return NO;
    }
    
    // Check if window is visible and key
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    if (!buttonWindow || ![buttonWindow isKeyWindow] || [buttonWindow isMiniaturized]) {
        return NO;
    }
    
    // Check if application is hidden
    if ([NSApp isHidden]) {
        return NO;
    }
    
    return YES;
}

// Handle control state changes (enabled/disabled) using KVO
- (void)observeValueForKeyPath:(NSString *)keyPath 
                      ofObject:(id)object 
                        change:(NSDictionary *)change 
                       context:(void *)context
{
    if ([keyPath isEqualToString:@"enabled"]) {
        NSDebugLog(@"DefaultButtonAnimationController: Button enabled state changed, checking animation state");
        
        // Redraw once so a freshly disabled button drops the pulse colour
        if ([buttoncell respondsToSelector:@selector(isEnabled)] && ![buttoncell isEnabled]) {
            NSDebugLog(@"DefaultButtonAnimationController: Button disabled - redrawing without pulse");
            [[buttoncell controlView] setNeedsDisplay: YES];
        }
        
        if ([self shouldAnimationBeRunning]) {
            if (pulseTimer == nil) {
                NSDebugLog(@"DefaultButtonAnimationController: Button became enabled and visible, starting animation");
                [self startPulse];
            }
        } else {
            if (pulseTimer != nil) {
                NSDebugLog(@"DefaultButtonAnimationController: Button became disabled or invisible, stopping animation");
                [self stopPulse];
            }
        }
    }
}
@end

// TS: forward dec
@interface NSWindow(EauTheme)
- (void) EAUsetDefaultButtonCell: (NSButtonCell *)aCell;
- (void) EAUinstallDefaultButtonCell: (NSButtonCell *)aCell;
@end

@implementation Eau(NSWindow)

// NSWindow.m standardWindowButton:forStyleMask: defers to the theme which
// implements this method (in the theme class).
- (NSButton *) standardWindowButton: (NSWindowButton)button
                       forStyleMask: (NSUInteger) mask
{
  NSDebugLog(@"NSWindow+Eau standardWindowButton:forStyleMask:");

  if (EauTitleBarButtonStyleIsOrb()) {
    EauWindowButton *orbButton = [[EauWindowButton alloc] init];
    [orbButton setRefusesFirstResponder: YES];
    [orbButton setButtonType: NSMomentaryChangeButton];
    [orbButton setImagePosition: NSImageOnly];
    [orbButton setBordered: YES];
    [orbButton setTag: button];

    switch (button) {
      case NSWindowCloseButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.97 green:0.26 blue:0.23 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Close"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_CloseH"]];
        [orbButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.9 green:0.7 blue:0.3 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Miniaturize"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_MiniaturizeH"]];
        [orbButton setAction: @selector(miniaturize:)];
        break;
      case NSWindowZoomButton:
        [orbButton setBaseColor: [NSColor colorWithCalibratedRed:0.322 green:0.778 blue:0.244 alpha:1]];
        [orbButton setImage: [NSImage imageNamed: @"common_Zoom"]];
        [orbButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
        [orbButton setAction: @selector(zoom:)];
        break;
      case NSWindowToolbarButton:
        [orbButton setAction: @selector(toggleToolbarShown:)];
        break;
      case NSWindowDocumentIconButton:
      default:
        break;
    }
    return orbButton;
  }

  EauTitleBarButton *newButton;

  switch (button)
    {
      case NSWindowCloseButton:
        newButton = [EauTitleBarButton closeButton];
        [newButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        newButton = [EauTitleBarButton minimizeButton];
        [newButton setAction: @selector(miniaturize:)];
        break;

      case NSWindowZoomButton:
        newButton = [EauTitleBarButton maximizeButton];
        [newButton setAction: @selector(zoom:)];
        break;

      case NSWindowToolbarButton:
        // FIXME - fallback to old style for toolbar button
        {
          EauWindowButton *oldButton = [[EauWindowButton alloc] init];
          [oldButton setAction: @selector(toggleToolbarShown:)];
          [oldButton setRefusesFirstResponder: YES];
          [oldButton setButtonType: NSMomentaryChangeButton];
          [oldButton setImagePosition: NSImageOnly];
          [oldButton setBordered: YES];
          [oldButton setTag: button];
          return oldButton;
        }
      case NSWindowDocumentIconButton:
      default:
        // FIXME - fallback to old style for document icon
        {
          EauWindowButton *oldButton = [[EauWindowButton alloc] init];
          [oldButton setRefusesFirstResponder: YES];
          [oldButton setButtonType: NSMomentaryChangeButton];
          [oldButton setImagePosition: NSImageOnly];
          [oldButton setBordered: YES];
          [oldButton setTag: button];
          return oldButton;
        }
    }

  [newButton setTag: button];
  return newButton;
}

- (void) _overrideNSWindowMethod_setDefaultButtonCell: (NSButtonCell *)aCell {
  NSDebugLog(@"_overrideNSWindowMethod_setDefaultButtonCell:");
  NSWindow *xself = (NSWindow*)self;
  [xself EAUsetDefaultButtonCell:aCell];
}

@end

@implementation NSWindow(EauTheme)

static const void *kEAUDefaultButtonControllerKey = &kEAUDefaultButtonControllerKey;
static const void *kEAUDefaultButtonInstallingKey = &kEAUDefaultButtonInstallingKey;

/* NSWindow keeps its delegate as a plain unretained reference, so the animation
 * controller has to be unhooked from the window *before* the association drops
 * the last reference to it.  Releasing it first leaves -delegate handing out a
 * freed object, which ARC then tries to retain. */
static void EAUReleaseDefaultButtonController(NSWindow *window)
{
  id controller = objc_getAssociatedObject(window, kEAUDefaultButtonControllerKey);

  if (controller == nil)
    {
      return;
    }

  if ([window delegate] == controller)
    {
      [window setDelegate: nil];
    }

  objc_setAssociatedObject(window,
                           kEAUDefaultButtonControllerKey,
                           nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

/* EAUsetDefaultButtonCell:
 * 
 * Custom implementation of setDefaultButtonCell: for the Eau theme.
 * This method is installed as a replacement for NSWindow's setDefaultButtonCell:
 * via the _overrideNSWindowMethod_setDefaultButtonCell: block architecture.
 * 
 * WHAT THIS DOES:
 * - Creates a DefaultButtonAnimationController to manage button pulsing animation
 * - Sets the button's key equivalent to Enter (\r) so pressing Enter activates it
 * - Marks the button cell as the default button (isDefaultButton = YES)
 * - Retains the controller via objc_setAssociatedObject to keep it alive
 * - CONDITIONALLY sets the controller as window delegate (NOT for GWDialog!)
 * 
 * WHY DELEGATE HANDLING IS CRITICAL:
 * GWDialog and other windows with text fields need special handling.
 * When an NSTextField becomes first responder, NSWindow calls the delegate method:
 *   [delegate windowWillReturnFieldEditor:toObject:]
 * 
 * PROBLEM: On ARM64, if this delegate method isn't properly implemented with the
 * correct type encoding, the Objective-C runtime can incorrectly use objc_msgSend_stret
 * (structure-return calling convention) instead of objc_msgSend (pointer-return
 * calling convention), causing a SIGSEGV crash when the field editor is requested.
 * 
 * SOLUTION: 
 * 1. For GWDialog: Don't set a delegate at all. The animation controller still works
 *    via NSNotificationCenter (windowDidBecomeKey, windowDidResignKey, etc.) and
 *    doesn't need to be a delegate.
 * 2. For other windows: Safely set the delegate after checking for existing delegates.
 * 3. DefaultButtonAnimationController implements windowWillReturnFieldEditor:toObject:
 *    returning nil, which tells NSWindow to use its default field editor.
 * 
 * FOCUS MANAGEMENT:
 * By not setting a delegate on GWDialog, we preserve the text field's
 * initialFirstResponder setup done in GWDialog+Eau.m, giving immediate focus
 * with a blinking cursor when dialogs open. Users can type immediately.
 */
- (void) EAUsetDefaultButtonCell: (NSButtonCell *)aCell
{
  NSDebugLog(@"NSWindow+Eau: EAUsetDefaultButtonCell called with cell %p for window %p", aCell, self);

  /* -setKeyEquivalent: below travels through GSTheme into the button and
   * button cell categories, which may hand this very cell to this window
   * again.  Letting that re-entry run would install a second controller for
   * the same cell and tear the first one down again as soon as the outer call
   * resumed. */
  if (aCell != nil
      && objc_getAssociatedObject(self, kEAUDefaultButtonInstallingKey) == aCell)
    {
      NSDebugLog(@"NSWindow+Eau: Ignoring re-entrant setDefaultButtonCell: for cell %p", aCell);
      return;
    }

  _defaultButtonCell = aCell;

  EAUReleaseDefaultButtonController(self);

  if (aCell == nil) {
    return;
  }

  objc_setAssociatedObject(self, kEAUDefaultButtonInstallingKey, aCell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  @try
    {
      [self EAUinstallDefaultButtonCell: aCell];
    }
  @finally
    {
      objc_setAssociatedObject(self, kEAUDefaultButtonInstallingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

/* Everything that actually wires the cell up as the window's default button.
 * Split out so the re-entrancy marker set by -EAUsetDefaultButtonCell: is
 * cleared again even if any of this raises. */
- (void) EAUinstallDefaultButtonCell: (NSButtonCell *)aCell
{
  [self enableKeyEquivalentForDefaultButtonCell];

  [aCell setKeyEquivalent: @"\r"];
  [aCell setKeyEquivalentModifierMask: 0];
  [aCell setIsDefaultButton: [NSNumber numberWithBool: YES]];

  NSDebugLog(@"NSWindow+Eau: Creating DefaultButtonAnimationController for cell %p", aCell);
  DefaultButtonAnimationController * animationcontroller = [[DefaultButtonAnimationController alloc] initWithButtonCell: aCell];

  // Retain controller via association to ensure it stays alive
  objc_setAssociatedObject(self,
                           kEAUDefaultButtonControllerKey,
                           animationcontroller,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  /* CRITICAL FOCUS MANAGEMENT:
   * We deliberately DO NOT set the animation controller as delegate for GWDialog.
   * 
   * Why? GWDialog has text fields that need focus when the dialog opens. When a
   * text field becomes first responder, NSWindow calls the delegate method
   * windowWillReturnFieldEditor:toObject: to get a field editor.
   * 
   * If we set a delegate here, there's a risk of:
   * 1. Method resolution issues causing objc_msgSend_stret crashes on ARM64
   * 2. Interfering with GWDialog's own text field management
   * 3. Breaking the initial first responder setup done in GWDialog+Eau.m
   * 
   * The animation controller doesn't need to be a delegate to work - it receives
   * window notifications (windowDidBecomeKey, windowDidResignKey, etc.) via
   * NSNotificationCenter, which is sufficient for controlling the button animation.
   * 
   * For other window types (non-GWDialog), we can safely set the delegate because
   * they typically don't have the same text field focus requirements on open.
   */
  if ([self isKindOfClass: NSClassFromString(@"GWDialog")])
    {
      NSDebugLog(@"NSWindow+Eau: Skipping delegate assignment for GWDialog %p to preserve text field focus", self);
    }
  else
    {
      // Guard against overriding existing delegates for non-GWDialog windows
      id currentDelegate = [self delegate];
      if (currentDelegate == nil || currentDelegate == animationcontroller)
        {
          NSDebugLog(@"NSWindow+Eau: Setting window delegate to animation controller %p for window %p", animationcontroller, self);
          [self setDelegate: animationcontroller];
        }
      else
        {
          NSDebugLog(@"NSWindow+Eau: Preserving existing delegate %@ for window %p", currentDelegate, self);
        }
    }
  
  NSDebugLog(@"NSWindow+Eau: Starting pulse animation for cell %p", aCell);
  [animationcontroller startPulse];
  
  NSDebugLog(@"NSWindow+Eau: Default button cell setup completed for cell %p", aCell);
}

- (void) animateDefaultButton: (id)sender
{
}

@end