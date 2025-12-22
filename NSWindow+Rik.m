#include "Rik+Button.h"
#include "RikWindowButton.h"
#include <AppKit/NSAnimation.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSImage.h>
#import "GNUstepGUI/GSTheme.h"

@interface DefaultButtonAnimation: NSAnimation
{
  NSButtonCell * defaultbuttoncell;
  BOOL reverse;
}

@property (nonatomic, assign) BOOL reverse;
@property (retain) NSButtonCell * defaultbuttoncell;

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
          RIKLOG(@"DefaultButtonAnimation: Button cell is disabled, stopping animation");
          defaultbuttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
          [[defaultbuttoncell controlView] setNeedsDisplay: YES];
          [self stopAnimation];
          return;
        }
    }
  if (defaultbuttoncell && progress >= 1.0)
  {
    reverse = !reverse;
    RIKLOG(@"DefaultButtonAnimation: Reversing direction and restarting animation");
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
  RIKLOG(@"DefaultButtonAnimationController: initWithButtonCell called with cell %p", cell);
  if (self = [super init]) {
    buttoncell = cell;
    
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
        RIKLOG(@"DefaultButtonAnimationController: Added KVO observer for enabled property on control %p", control);
      }
      @catch (NSException *exception) {
        RIKLOG(@"DefaultButtonAnimationController: ERROR adding KVO observer for enabled property: %@", exception);
      }
    }
    
    RIKLOG(@"DefaultButtonAnimationController: Successfully initialized with cell %p", cell);
  }
  return self;
}

- (void) dealloc
{
  RIKLOG(@"DefaultButtonAnimationController: dealloc called for cell %p", buttoncell);
  
  // Stop animation and remove all notifications
  [animation stopAnimation];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  // Remove KVO observer for enabled property
  if ([buttoncell controlView]) {
    NSControl *control = (NSControl *)[buttoncell controlView];
    @try {
      [control removeObserver:self forKeyPath:@"enabled"];
      RIKLOG(@"DefaultButtonAnimationController: Removed KVO observer for enabled property on control %p", control);
    }
    @catch (NSException *exception) {
      RIKLOG(@"DefaultButtonAnimationController: ERROR removing KVO observer for enabled property: %@", exception);
    }
  }
  
  [animation release];
  [super dealloc];
}

- (void) startPulse
{
  RIKLOG(@"DefaultButtonAnimationController: startPulse called for cell %p", buttoncell);
  [self startPulse: NO];
}
- (void) startPulse: (BOOL) reverse
{
  RIKLOG(@"DefaultButtonAnimationController: startPulse:reverse called with reverse=%d for cell %p", reverse, buttoncell);
  
  // Check if the button cell is enabled before starting animation
  BOOL isEnabled = YES;
  if ([buttoncell respondsToSelector:@selector(isEnabled)]) {
    isEnabled = [buttoncell isEnabled];
  }
  
  if (!isEnabled) {
    RIKLOG(@"DefaultButtonAnimationController: Button cell is disabled, not starting animation");
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
  
  RIKLOG(@"DefaultButtonAnimationController: Starting animation %p for cell %p", animation, buttoncell);
  [animation startAnimation];
  RIKLOG(@"DefaultButtonAnimationController: Animation started for cell %p", buttoncell);
}
- (void)animation:(NSAnimation *)a
            didReachProgressMark:(NSAnimationProgress)progress
{
  //[animation stopAnimation];
  //[self startPulse: !animation.reverse];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
      RIKLOG(@"DefaultButtonAnimationController: Window resigned key, stopping animation");
      [animation stopAnimation];
}

// TS: added this method
- (void)windowDidBecomeKey:(NSNotification *)notification
{
      if ([self shouldAnimationBeRunning]) {
          RIKLOG(@"DefaultButtonAnimationController: Window became key and button is enabled, starting animation");
          [animation startAnimation];
      } else {
          RIKLOG(@"DefaultButtonAnimationController: Window became key but button is disabled, not starting animation");
      }
}

// Additional notification handlers for proper visibility management
- (void)windowWillClose:(NSNotification *)notification
{
    NSWindow *closingWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (closingWindow == buttonWindow) {
        RIKLOG(@"DefaultButtonAnimationController: Button's window is closing, stopping animation");
        [animation stopAnimation];
    }
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    NSWindow *miniaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (miniaturizedWindow == buttonWindow) {
        RIKLOG(@"DefaultButtonAnimationController: Button's window was miniaturized, stopping animation");
        [animation stopAnimation];
    }
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    NSWindow *deminiaturizedWindow = [notification object];
    NSWindow *buttonWindow = [[buttoncell controlView] window];
    
    if (deminiaturizedWindow == buttonWindow && [self shouldAnimationBeRunning]) {
        RIKLOG(@"DefaultButtonAnimationController: Button's window was deminiaturized and button is enabled, starting animation");
        [animation startAnimation];
    }
}

- (void)applicationDidHide:(NSNotification *)notification
{
    RIKLOG(@"DefaultButtonAnimationController: Application was hidden, stopping animation");
    [animation stopAnimation];
}

- (void)applicationDidUnhide:(NSNotification *)notification
{
    if ([self shouldAnimationBeRunning]) {
        RIKLOG(@"DefaultButtonAnimationController: Application was unhidden and button is enabled and visible, starting animation");
        [animation startAnimation];
    } else {
        RIKLOG(@"DefaultButtonAnimationController: Application was unhidden but button is disabled or window not visible, not starting animation");
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
        RIKLOG(@"DefaultButtonAnimationController: Button enabled state changed, checking animation state");
        
        // Immediately reset pulse progress if button becomes disabled
        if ([buttoncell respondsToSelector:@selector(isEnabled)] && ![buttoncell isEnabled]) {
            RIKLOG(@"DefaultButtonAnimationController: Button disabled - immediately resetting pulse progress");
            buttoncell.pulseProgress = [NSNumber numberWithFloat: 0.0];
            [[buttoncell controlView] setNeedsDisplay: YES];
        }
        
        if ([self shouldAnimationBeRunning]) {
            if (![animation isAnimating]) {
                RIKLOG(@"DefaultButtonAnimationController: Button became enabled and visible, starting animation");
                [self startPulse];
            }
        } else {
            if ([animation isAnimating]) {
                RIKLOG(@"DefaultButtonAnimationController: Button became disabled or invisible, stopping animation");
                [animation stopAnimation];
            }
        }
    }
}
@end

// TS: forward dec
@interface NSWindow(RikTheme)
- (void) RIKsetDefaultButtonCell: (NSButtonCell *)aCell;
- (void) RIKcenter;
@end

@implementation Rik(NSWindow)

// NSWindow.m standardWindowButton:forStyleMask: defers to the theme which
// implements this method (in the theme class).
- (NSButton *) standardWindowButton: (NSWindowButton)button
                       forStyleMask: (NSUInteger) mask
{
  RikWindowButton *newButton;

  RIKLOG(@"NSWindow+Rik standardWindowButton:forStyleMask:");

  switch (button)
    {
      case NSWindowCloseButton:
        newButton = [[RikWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.97 green: 0.26 blue: 0.23 alpha: 1.0]];
        [newButton setImage: [NSImage imageNamed: @"common_Close"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_CloseH"]];
        [newButton setAction: @selector(performClose:)];
        break;
      case NSWindowMiniaturizeButton:
        newButton = [[RikWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.9 green: 0.7 blue: 0.3 alpha: 1]];
        [newButton setImage: [NSImage imageNamed: @"common_Miniaturize"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_MiniaturizeH"]];
        [newButton setAction: @selector(miniaturize:)];
        break;

      case NSWindowZoomButton:
        newButton = [[RikWindowButton alloc] init];
        [newButton setBaseColor: [NSColor colorWithCalibratedRed: 0.322 green: 0.778 blue: 0.244 alpha: 1]];
        [newButton setImage: [NSImage imageNamed: @"common_Zoom"]];
        [newButton setAlternateImage: [NSImage imageNamed: @"common_ZoomH"]];
        [newButton setAction: @selector(zoom:)];
        break;

      case NSWindowToolbarButton:
        // FIXME
        newButton = [[RikWindowButton alloc] init];
        [newButton setAction: @selector(toggleToolbarShown:)];
        break;
      case NSWindowDocumentIconButton:
      default:
        newButton = [[RikWindowButton alloc] init];
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
  RIKLOG(@"_overrideNSWindowMethod_setDefaultButtonCell:");
  NSWindow *xself = (NSWindow*)self;
  [xself RIKsetDefaultButtonCell:aCell];
}

// Override the center method to position windows using golden ratio
- (void) _overrideNSWindowMethod_center {
  RIKLOG(@"_overrideNSWindowMethod_center: Positioning window with golden ratio");
  NSWindow *xself = (NSWindow*)self;
  [xself RIKcenter];
}

@end

@implementation NSWindow(RikTheme)

- (void) RIKsetDefaultButtonCell: (NSButtonCell *)aCell
{
  RIKLOG(@"NSWindow+Rik: RIKsetDefaultButtonCell called with cell %p", aCell);
  
  ASSIGN(_defaultButtonCell, aCell);
  [self enableKeyEquivalentForDefaultButtonCell];

  [aCell setKeyEquivalent: @"\r"];
  [aCell setKeyEquivalentModifierMask: 0];
  [aCell setIsDefaultButton: [NSNumber numberWithBool: YES]];

  RIKLOG(@"NSWindow+Rik: Creating DefaultButtonAnimationController for cell %p", aCell);
  DefaultButtonAnimationController * animationcontroller = [[DefaultButtonAnimationController alloc] initWithButtonCell: aCell];
  
  RIKLOG(@"NSWindow+Rik: Setting window delegate to animation controller %p", animationcontroller);
  [self setDelegate:animationcontroller];
  
  RIKLOG(@"NSWindow+Rik: Starting pulse animation for cell %p", aCell);
  [animationcontroller startPulse];
  
  RIKLOG(@"NSWindow+Rik: Default button cell setup completed for cell %p", aCell);
}

- (void) animateDefaultButton: (id)sender
{
}

// Golden ratio positioning method
- (void) RIKcenter
{
  RIKLOG(@"NSWindow+Rik: RIKcenter called - applying golden ratio positioning");
  
  NSScreen *screen = [self screen];
  if (!screen) {
    screen = [NSScreen mainScreen];
  }
  
  if (!screen) {
    RIKLOG(@"NSWindow+Rik: No screen available, using standard center");
    [self center];
    return;
  }
  
  NSRect screenFrame = [screen visibleFrame];
  NSRect windowFrame = [self frame];
  
  RIKLOG(@"NSWindow+Rik: Screen frame: %@", NSStringFromRect(screenFrame));
  RIKLOG(@"NSWindow+Rik: Window frame: %@", NSStringFromRect(windowFrame));
  
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
  
  RIKLOG(@"NSWindow+Rik: New window frame with golden ratio: %@", NSStringFromRect(newFrame));
  
  [self setFrame:newFrame display:YES];
}

@end