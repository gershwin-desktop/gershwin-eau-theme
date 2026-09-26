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
#import "Behaviors/GBThemeHooks+DefaultButton.h"
#import "Behaviors/GBThemeHooks+Window.h"

@interface DefaultButtonAnimationController : NSObject

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

  if (cell == nil)
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

static const void *kEAUDefaultButtonControllerKey = &kEAUDefaultButtonControllerKey;

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

/* GershwinBehaviors decides which cell is a window's default button and
 * reports every change here; the theme only owns the pulse.  The controller
 * lives on the window, so a new default button (or none) retires the old
 * pulse together with its timer. */
- (void) gbDefaultButtonCellChanged: (NSButtonCell *)cell forWindow: (NSWindow *)window
{
  if (window == nil)
    {
      return;
    }

  objc_setAssociatedObject(window, kEAUDefaultButtonControllerKey, nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  if (cell == nil)
    {
      return;
    }

  [cell setIsDefaultButton: [NSNumber numberWithBool: YES]];

  DefaultButtonAnimationController *controller =
    [[DefaultButtonAnimationController alloc] initWithButtonCell: cell];
  objc_setAssociatedObject(window, kEAUDefaultButtonControllerKey, controller,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  [controller startPulse];
}

/* The grow box has to be in place before the window's first frame. */
- (void) gbWindowWillOrderFront: (NSWindow *)window
{
  [EauGrowBoxView addToWindow: window];
}

@end

@implementation NSWindow(EauTheme)

- (void) animateDefaultButton: (id)sender
{
}

@end