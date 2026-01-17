#include "Eau+Button.h"
#include "EauWindowButton.h"
#include "EauGrowBoxView.h"
#include <AppKit/NSAnimation.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSAlert.h>
#import "GNUstepGUI/GSTheme.h"
#import <objc/runtime.h>

@interface DefaultButtonAnimation: NSAnimation
{
  NSButtonCell * defaultbuttoncell;
  BOOL reverse;
}

@property (nonatomic, assign) BOOL reverse;
@property (retain) NSButtonCell * defaultbuttoncell;

@end

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
  if (view == nil)
    {
      return;
    }
  if ([view isKindOfClass: [NSTextField class]])
    {
      NSTextField *field = (NSTextField *)view;
      NSString *value = [field stringValue];
      if (value != nil && [value length] > 0)
        {
          [parts addObject: value];
        }
    }
  NSArray *subviews = [view subviews];
  NSUInteger count = [subviews count];
  for (NSUInteger i = 0; i < count; i++)
    {
      EAUCollectDialogTextFromView(parts, [subviews objectAtIndex: i]);
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
      EAULOG(@"EauWindowLog: %@ window=(null)", event);
      return;
    }
  NSString *summary = nil;
  if (EAUIsDialogWindow(window))
    {
      summary = EAUDialogTextSummary(window);
    }
  EAULOG(@"EauWindowLog: %@ window=%p class=%@ title='%@' visible=%d key=%d main=%d level=%ld",
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
      EAULOG(@"EauDialog: window=%p class=%@ text='%@'", window, NSStringFromClass([window class]), summary);
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
  [EauGrowBoxView addToWindow:self];
  [self eau_orderFront: sender];
}

- (void) eau_orderFrontRegardless
{
  EAUWindowLog(@"orderFrontRegardless", self);
  [EauGrowBoxView addToWindow:self];
  [self eau_orderFrontRegardless];
}

- (void) eau_makeKeyAndOrderFront: (id)sender
{
  EAUWindowLog(@"makeKeyAndOrderFront", self);
  [EauGrowBoxView addToWindow:self];
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

@implementation DefaultButtonAnimation

@synthesize reverse;
@synthesize defaultbuttoncell;

- (void)setCurrentProgress:(NSAnimationProgress)progress
{
  [super setCurrentProgress: progress];
  if(defaultbuttoncell)
    {
        // Check if the button cell is enabled before updating pulse progress
        BOOL isEnabled = YES;
        if ([defaultbuttoncell respondsToSelector:@selector(isEnabled)]) {
          isEnabled = [defaultbuttoncell isEnabled];
        }
        
        if (isEnabled) {
          if(reverse)
          {
            defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: 1.0 - progress];
          }else{
            defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: progress];
          }
          [[defaultbuttoncell controlView] setNeedsDisplay: YES];
        } else {
          // Button is disabled, stop the animation and reset pulse progress
          EAULOG(@"DefaultButtonAnimation: Button cell is disabled, stopping animation");
          defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
          [[defaultbuttoncell controlView] setNeedsDisplay: YES];
          [self stopAnimation];
          return;
        }
    }
  if (defaultbuttoncell && progress >= 1.0)
  {
    reverse = !reverse;
    EAULOG(@"DefaultButtonAnimation: Reversing direction and restarting animation");
    [self startAnimation];
  }
}
@end

@interface DefaultButtonAnimationController : NSObject <NSWindowDelegate>

{
  DefaultButtonAnimation * animation;
  NSButtonCell * buttoncell;
}

@property (retain) NSButtonCell * buttoncell;
@property (retain) NSAnimation * animation;

@end
@implementation DefaultButtonAnimationController
@synthesize buttoncell;
@synthesize animation;
- (id) initWithButtonCell: (NSButtonCell*) cell
{
  EAULOG(@"DefaultButtonAnimationController: initWithButtonCell called with cell %p", cell);
  if (self = [super init]) {
    buttoncell = cell;    EAULOG(@"DefaultButtonAnimationController: Initialized for button cell %p", cell);    
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
        EAULOG(@"DefaultButtonAnimationController: Added KVO observer for enabled property on control %p", control);
      }
      @catch (NSException *exception) {
        EAULOG(@"DefaultButtonAnimationController: ERROR adding KVO observer for enabled property: %@", exception);
      }
    }
    
    EAULOG(@"DefaultButtonAnimationController: Successfully initialized with cell %p", cell);
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
  EAULOG(@"DefaultButtonAnimationController: windowWillReturnFieldEditor called for object %p, returning nil (use default)", anObject);
  return nil;  // Return nil to use the default field editor
}


- (void) dealloc
{
  EAULOG(@"DefaultButtonAnimationController: dealloc called for cell %p", buttoncell);
  
  // Stop animation and remove all notifications
  [animation stopAnimation];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  // Remove KVO observer for enabled property
  if ([buttoncell controlView]) {
    NSControl *control = (NSControl *)[buttoncell controlView];
    @try {
      [control removeObserver:self forKeyPath:@"enabled"];
      EAULOG(@"DefaultButtonAnimationController: Removed KVO observer for enabled property on control %p", control);
    }
    @catch (NSException *exception) {
      EAULOG(@"DefaultButtonAnimationController: ERROR removing KVO observer for enabled property: %@", exception);
    }
  }
  
  [animation release];
  [super dealloc];
}

- (void) startPulse
{
  EAULOG(@"DefaultButtonAnimationController: startPulse called for cell %p", buttoncell);
  [self startPulse: NO];
}
- (void) startPulse: (BOOL) reverse
{
  EAULOG(@"DefaultButtonAnimationController: startPulse:reverse called with reverse=%d for cell %p", reverse, buttoncell);
  
  // Check if the button cell is enabled before starting animation
  BOOL isEnabled = YES;
  if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
    isEnabled = [buttoncell isEnabled];
  }
  
  if (!isEnabled) {
    EAULOG(@"DefaultButtonAnimationController: Button cell is disabled, not starting animation");
    return;
  }
  
  animation = [[DefaultButtonAnimation alloc] initWithDuration:0.7
                                animationCurve:NSAnimationEaseInOut];
  animation.reverse = reverse;
  [animation addProgressMark: 1.0];
  [animation setDelegate: self];
  [animation setFrameRate:30.0];
  [animation setAnimationBlockingMode:NSAnimationNonblocking];
  animation.defaultbuttoncell = buttoncell;
  
  EAULOG(@"DefaultButtonAnimationController: Starting animation %p for cell %p", animation, buttoncell);
  [animation startAnimation];
  EAULOG(@"DefaultButtonAnimationController: Animation started for cell %p", buttoncell);
}
- (void)animation:(NSAnimation *)a
            didReachProgressMark:(NSAnimationProgress)progress
{
  //[animation stopAnimation];
  //[self startPulse: !animation.reverse];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
      EAULOG(@"DefaultButtonAnimationController: Window resigned key, stopping animation");
      [animation stopAnimation];
}

// TS: added this method
- (void)windowDidBecomeKey:(NSNotification *)notification
{
      NSWindow *window = [notification object];
      NSWindow *buttonWindow = [[buttoncell controlView] window];
      
      EAULOG(@"DefaultButtonAnimationController: Window became key notification received");
      EAULOG(@"DefaultButtonAnimationController: Notifying window %p, button window %p", window, buttonWindow);
      
      if (window == buttonWindow)
        {
          if ([self shouldAnimationBeRunning]) {
              EAULOG(@"DefaultButtonAnimationController: Button's window became key and button is enabled, starting animation");
              [animation startAnimation];
          } else {
              EAULOG(@"DefaultButtonAnimationController: Button's window became key but button is disabled, not starting animation");
          }
        }
      else
        {
          EAULOG(@"DefaultButtonAnimationController: Different window became key, ignoring");
        }
}

// Additional notification handlers for proper visibility management
- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *closingWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (closingWindow == buttonWindow) {
        EAULOG(@"DefaultButtonAnimationController: Button's window is closing, stopping animation");
        [animation stopAnimation];
    }
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    NSWindow *miniaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (miniaturizedWindow == buttonWindow) {
        EAULOG(@"DefaultButtonAnimationController: Button's window was miniaturized, stopping animation");
        [animation stopAnimation];
    }
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    NSWindow *deminiaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (deminiaturizedWindow == buttonWindow && [self shouldAnimationBeRunning]) {
        EAULOG(@"DefaultButtonAnimationController: Button's window was deminiaturized and button is enabled, starting animation");
        [animation startAnimation];
    }
}

- (void)applicationDidHide:(NSNotification *)notification
{
    EAULOG(@"DefaultButtonAnimationController: Application was hidden, stopping animation");
    [animation stopAnimation];
}

- (void)applicationDidUnhide:(NSNotification *)notification
{
    if ([self shouldAnimationBeRunning]) {
        EAULOG(@"DefaultButtonAnimationController: Application was unhidden and button is enabled and visible, starting animation");
        [animation startAnimation];
    } else {
        EAULOG(@"DefaultButtonAnimationController: Application was unhidden but button is disabled or window not visible, not starting animation");
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
        EAULOG(@"DefaultButtonAnimationController: Button enabled state changed, checking animation state");
        
        // Immediately reset pulse progress if button becomes disabled
        if ([buttoncell respondsToSelector:@selector(isEnabled)] && ![buttoncell isEnabled]) {
            EAULOG(@"DefaultButtonAnimationController: Button disabled - immediately resetting pulse progress");
            buttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
            [[buttoncell controlView] setNeedsDisplay: YES];
        }
        
        if ([self shouldAnimationBeRunning]) {
            if (![animation isAnimating]) {
                EAULOG(@"DefaultButtonAnimationController: Button became enabled and visible, starting animation");
                [self startPulse];
            }
        } else {
            if ([animation isAnimating]) {
                EAULOG(@"DefaultButtonAnimationController: Button became disabled or invisible, stopping animation");
                [animation stopAnimation];
            }
        }
    }
}
@end

// TS: forward dec
@interface NSWindow(EauTheme)
- (void) EAUsetDefaultButtonCell: (NSButtonCell *)aCell;
- (void) EAUcenter;
@end

@implementation Eau(NSWindow)

// NSWindow.m standardWindowButton:forStyleMask: defers to the theme which
// implements this method (in the theme class).
- (NSButton *) standardWindowButton: (NSWindowButton)button
                       forStyleMask: (NSUInteger) mask
{
  EauWindowButton *newButton;

  EAULOG(@"NSWindow+Eau standardWindowButton:forStyleMask:");

  switch (button)
    {
      case NSWindowCloseButton:
        newButton = [[EauWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.97 green: 0.26 blue: 0.23 alpha: 1.0]];
        [newButton setImage: [NSImage imageNamed: @"common_Close"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_CloseH"]];
        [newButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        newButton = [[EauWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.9 green: 0.7 blue: 0.3 alpha: 1]];
        [newButton setImage: [NSImage imageNamed: @"common_Miniaturize"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_MiniaturizeH"]];
        [newButton setAction: @selector(miniaturize:)];
        break;

      case NSWindowZoomButton:
        newButton = [[EauWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.322 green: 0.778 blue: 0.244 alpha: 1]];
        [newButton setImage: [NSImage imageNamed: @"common_Zoom"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
        [newButton setAction: @selector(zoom:)];
        break;

      case NSWindowToolbarButton:
        // FIXME
        newButton = [[EauWindowButton alloc] init];
        [newButton setAction: @selector(toggleToolbarShown:)];
        break;
      case NSWindowDocumentIconButton:
      default:
        newButton = [[EauWindowButton alloc] init];
        // FIXME
        break;
    }

  [newButton setRefusesFirstResponder: YES];
  [newButton setButtonType: NSMomentaryChangeButton];
  [newButton setImagePosition: NSImageOnly];
  [newButton setBordered: YES];
  [newButton setTag: button];
  return AUTORELEASE(newButton);
}

- (void) _overrideNSWindowMethod_setDefaultButtonCell: (NSButtonCell *)aCell {
  EAULOG(@"_overrideNSWindowMethod_setDefaultButtonCell:");
  NSWindow *xself = (NSWindow*)self;
  [xself EAUsetDefaultButtonCell:aCell];
}

// Override the center method to position windows using golden ratio
- (void) _overrideNSWindowMethod_center {
  EAULOG(@"_overrideNSWindowMethod_center: Positioning window with golden ratio");
  NSWindow *xself = (NSWindow*)self;
  [xself EAUcenter];
}

@end

@implementation NSWindow(EauTheme)

static const void *kEAUDefaultButtonControllerKey = &kEAUDefaultButtonControllerKey;

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
  EAULOG(@"NSWindow+Eau: EAUsetDefaultButtonCell called with cell %p", aCell);
  
  ASSIGN(_defaultButtonCell, aCell);
  [self enableKeyEquivalentForDefaultButtonCell];

  [aCell setKeyEquivalent: @"\r"];
  [aCell setKeyEquivalentModifierMask: 0];
  [aCell setIsDefaultButton: [NSNumber numberWithBool: YES]];

  EAULOG(@"NSWindow+Eau: Creating DefaultButtonAnimationController for cell %p", aCell);
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
      EAULOG(@"NSWindow+Eau: Skipping delegate assignment for GWDialog %p to preserve text field focus", self);
    }
  else
    {
      // Guard against overriding existing delegates for non-GWDialog windows
      id currentDelegate = [self delegate];
      if (currentDelegate == nil || currentDelegate == animationcontroller)
        {
          EAULOG(@"NSWindow+Eau: Setting window delegate to animation controller %p for window %p", animationcontroller, self);
          [self setDelegate: animationcontroller];
        }
      else
        {
          EAULOG(@"NSWindow+Eau: Preserving existing delegate %@ for window %p", currentDelegate, self);
        }
    }
  
  EAULOG(@"NSWindow+Eau: Starting pulse animation for cell %p", aCell);
  [animationcontroller startPulse];
  [animationcontroller release];
  
  EAULOG(@"NSWindow+Eau: Default button cell setup completed for cell %p", aCell);
}

- (void) animateDefaultButton: (id)sender
{
}

// Golden ratio positioning method
- (void) EAUcenter
{
  EAULOG(@"NSWindow+Eau: EAUcenter called - applying golden ratio positioning");
  
  NSScreen *screen = [self screen];
  if (!screen) {
    screen = [NSScreen mainScreen];
  }
  
  if (!screen) {
    EAULOG(@"NSWindow+Eau: No screen available, using standard center");
    [self center];
    return;
  }
  
  NSRect screenFrame = [screen visibleFrame];
  NSRect windowFrame = [self frame];
  
  EAULOG(@"NSWindow+Eau: Screen frame: %@", NSStringFromRect(screenFrame));
  EAULOG(@"NSWindow+Eau: Window frame: %@", NSStringFromRect(windowFrame));
  
  // Golden ratio ≈ 1.618, inverse ≈ 0.618
  // Position the window vertically at the golden ratio point
  const CGFloat goldenRatio = 1.618033988749;
  const CGFloat goldenRatioInverse = 1.0 / goldenRatio; // ≈ 0.618
  
  // Calculate horizontal center (keep this centered)
  CGFloat x = screenFrame.origin.x + (screenFrame.size.width - windowFrame.size.width) / 2.0;
  
  // Calculate vertical position using golden ratio
  // Position the window so that the ratio of space above to space below follows golden ratio
  // This places the window slightly above center, which is more visually pleasing
  CGFloat availableHeight = screenFrame.size.height - windowFrame.size.height;
  CGFloat y = screenFrame.origin.y + availableHeight * goldenRatioInverse;
  
  // Ensure the window stays within screen bounds
  if (x < screenFrame.origin.x) {
    x = screenFrame.origin.x;
  } else if (x + windowFrame.size.width > screenFrame.origin.x + screenFrame.size.width) {
    x = screenFrame.origin.x + screenFrame.size.width - windowFrame.size.width;
  }
  
  if (y < screenFrame.origin.y) {
    y = screenFrame.origin.y;
  } else if (y + windowFrame.size.height > screenFrame.origin.y + screenFrame.size.height) {
    y = screenFrame.origin.y + screenFrame.size.height - windowFrame.size.height;
  }
  
  NSRect newFrame = NSMakeRect(x, y, windowFrame.size.width, windowFrame.size.height);
  
  EAULOG(@"NSWindow+Eau: New window frame with golden ratio: %@", NSStringFromRect(newFrame));
  
  [self setFrame:newFrame display:YES];
}

@end