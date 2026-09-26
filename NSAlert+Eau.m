//
// NSAlert+Eau.m
//
// Comprehensive NSAlert customization for Eau theme.
// Replaces GSAlertPanel with EauAlertPanel for full control over appearance.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "NSAlert+Eau.h"
#import "Eau.h"
#import "AppearanceMetrics.h"

// Import centralized layout constants from AppearanceMetrics.h

#define useControl(control) ([control superview] != nil)

// Forward declarations
static void setControl(NSView *content, id control, NSString *title);
static void setButton(NSView *content, NSButton *control, NSButton *templateBtn);
static void setKeyEquivalent(NSButton *button);
static NSScrollView *makeScrollViewWithRect(NSRect rect);

// Declare -beep on NSApplication so callers in this file don't warn at compile time
@interface NSApplication (EauBeep)
- (void)beep;
@end

// Private category to declare swizzled selectors so the compiler knows about them
@interface EauAlertPanel (Swizzles)
- (id)eau_initWithoutGModel;
- (id)eau_initWithoutGModelHelper __attribute__((objc_method_family(init)));
@end

#pragma mark - EauAlertPanel Implementation

// Re-entrant guard flag, stored as an associated object so EauAlertPanel
// method implementations are safe to swizzle onto any class (e.g., GSAlertPanel)
// that shares the same ivar layout but lacks a dedicated _isStoppingModal ivar.
static const void *kEAUAlertIsStoppingKey = &kEAUAlertIsStoppingKey;
static const void *kEAUAlertWindowRetainKey = &kEAUAlertWindowRetainKey;

static BOOL eauAlertIsStopping(id panel)
{
    return [objc_getAssociatedObject(panel, kEAUAlertIsStoppingKey) boolValue];
}

static void eauAlertSetStopping(id panel, BOOL val)
{
    objc_setAssociatedObject(panel,
                             kEAUAlertIsStoppingKey,
                             @(val),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@implementation EauAlertPanel

+ (void) initialize
{
    if (self == [EauAlertPanel class])
    {
        [self setVersion: 1];
    }
}

- (id) initWithContentRect: (NSRect)rect
{
    // NSLog(@"Eau: EauAlertPanel initWithContentRect called");
    self = [super initWithContentRect: rect
                            styleMask: NSTitledWindowMask
                              backing: NSBackingStoreRetained
                                defer: YES];
    if (self == nil)
    {
        // NSLog(@"Eau: EauAlertPanel super init returned nil");
        return nil;
    }
    
    // NSLog(@"Eau: EauAlertPanel setting properties");
    [self setTitle: @" "];
    [self setLevel: NSModalPanelWindowLevel];
    [self setHidesOnDeactivate: NO];
    [self setBecomesKeyOnlyIfNeeded: NO];
    // One-shot: destroys the X11 back-end window when ordered out (during
    // alert dismissal).  This prevents a crash at dealloc time: NSWindow
    // dealloc calls _terminateBackendWindow, but if the X11 window was
    // already destroyed, _windowNum is 0 and _terminateBackendWindow is
    // safely skipped.  Without this, _terminateBackendWindow in dealloc
    // tries to destroy the X11 window and crashes (segfault).
    // TODO: Upstream to GNUstep - NSWindow dealloc (_terminateBackendWindow)
    // should tolerate a back-end window that is already gone.
    [self setOneShot: YES];
    
    NSView *content = [self contentView];
    NSFont *titleFont = METRICS_FONT_SYSTEM_BOLD_13;
    
    // Icon button - positioned at top left
    NSRect iconRect = NSMakeRect(METRICS_ICON_LEFT, 
                                  rect.size.height - METRICS_ICON_TOP - METRICS_ICON_SIDE,
                                  METRICS_ICON_SIDE, METRICS_ICON_SIDE);
    icoButton = [[NSButton alloc] initWithFrame: iconRect];
    [icoButton setAutoresizingMask: NSViewMaxXMargin | NSViewMinYMargin];
    [icoButton setBordered: NO];
    [icoButton setEnabled: NO];
    [icoButton setTitle: @""];   // Never show the default "Button" text
    [[icoButton cell] setImageDimsWhenDisabled: NO];
    [[icoButton cell] setImageScaling: NSImageScaleProportionallyUpOrDown];
    [icoButton setImagePosition: NSImageOnly];
    [icoButton setImage: [[NSApplication sharedApplication] applicationIconImage]];
    [content addSubview: icoButton];
    
    // Title field - positioned to the right of icon, top aligned
    NSRect titleRect = NSMakeRect(METRICS_TEXT_LEFT, 0, 0, 0);
    titleField = [[NSTextField alloc] initWithFrame: titleRect];
    [titleField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [titleField setEditable: NO];
    [titleField setSelectable: NO];
    [titleField setBezeled: NO];
    [titleField setDrawsBackground: NO];
    [titleField setStringValue: @""];
    [titleField setFont: titleFont];
    [titleField setAlignment: NSLeftTextAlignment];
    
    // NO horizontal line - this is what we want to remove from the default appearance
    // The default GSAlertPanel adds an NSBox with NSGrooveBorder here
    // We intentionally omit it for the Eau theme
    
    // Message field - positioned below title, same left alignment
    messageField = [[NSTextField alloc] initWithFrame: NSZeroRect];
    [messageField setEditable: NO];
    [messageField setSelectable: YES];
    [messageField setBezeled: NO];
    [messageField setDrawsBackground: NO];
    [messageField setAlignment: NSLeftTextAlignment];
    [messageField setStringValue: @""];
    [messageField setFont: METRICS_FONT_SYSTEM_REGULAR_11];
    [[messageField cell] setWraps: YES];
    [[messageField cell] setLineBreakMode: NSLineBreakByWordWrapping];
    
    // Buttons
    defButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertDefaultReturn];
    [defButton setKeyEquivalent: @"\r"];
    // // NSLog(@"Eau: defButton key equivalent set to: '%@' - FORCED LOG", [defButton keyEquivalent]);
    [defButton setHighlightsBy: NSPushInCellMask | NSChangeGrayCellMask | NSContentsCellMask];
    @try {
        [defButton setImagePosition: NSImageRight];
        [defButton setImage: [NSImage imageNamed: @"common_ret"]];
        [defButton setAlternateImage: [NSImage imageNamed: @"common_retH"]];
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception loading button images: %@", e);
    }
    /* Only the headline is bold; buttons always use the regular font.  The
     * default button is still marked as such by cell/button-behavior, not by
     * its font weight. */
    [defButton setFont: METRICS_FONT_SYSTEM_REGULAR_13];
    
    altButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertAlternateReturn];
    othButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertOtherReturn];
    
    // Scroll view for long messages
    scroll = makeScrollViewWithRect(NSMakeRect(0, 0, 80, 80));
    
    result = NSAlertErrorReturn;
    isGreen = YES;

    // NSLog(@"Eau: EauAlertPanel initWithContentRect completed successfully");
    return self;
}

- (id) init
{
    // NSLog(@"Eau: EauAlertPanel init called");

    // Compute a centered initial frame so the X window is never created at
    // (0,0) (bottom-left in OS coordinates).  This prevents a visual flash
    // where the alert appears near the bottom-left corner before -center
    // repositions it.  Use visibleFrame to stay within the usable screen area.
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat winW = METRICS_WIN_MIN_WIDTH;
    CGFloat winH = METRICS_WIN_MIN_HEIGHT;
    CGFloat screenW = [screen visibleFrame].size.width;
    CGFloat screenH = [screen visibleFrame].size.height;
    CGFloat x = ([screen visibleFrame].origin.x
                 + (screenW - winW) / 2);
    CGFloat y = ([screen visibleFrame].origin.y
                 + (screenH - winH) / 2);

    return [self initWithContentRect: NSMakeRect(x, y, winW, winH)];
}

// Helper method injected into GSAlertPanel via swizzling.
// Instead of building a GSAlertPanel (the old look), morphs `self` into an
// EauAlertPanel at the ObjC runtime level so it renders with full Eau metrics.
//
// GSAlertPanel and EauAlertPanel have identical ivar layouts (same ivars, same
// types, same order), so object_setClass() is safe — every ivar access resolves
// to the correct offset regardless of which class's method table we dispatch
// through.  The only previous difference was a _isStoppingModal ivar on
// EauAlertPanel, which has been refactored into an associated object
// (eauAlertIsStopping / eauAlertSetStopping) so the instance sizes match.
- (id) eau_initWithoutGModelHelper
{
    // Do NOT call the original GSAlertPanel _initWithoutGModel — we're building
    // an EauAlertPanel from scratch instead.

    // Morph this GSAlertPanel instance into an EauAlertPanel.
    // GSAlertPanel and EauAlertPanel have identical ivar layouts (the old
    // _isStoppingModal ivar was refactored into an associated object), so
    // object_setClass() is safe.
    object_setClass(self, [EauAlertPanel class]);

    // Call EauAlertPanel's initWithContentRect: directly (not init, to avoid ARC
    // self-assignment constraints in non-init-family helper methods).  This
    // initializes the NSPanel part and creates all subviews with Eau metrics
    // from AppearanceMetrics.h.
    //
    // Compute a centered initial frame the same way EauAlertPanel.init does.
    NSScreen *screen = [NSScreen mainScreen];
    CGFloat winW = METRICS_WIN_MIN_WIDTH;
    CGFloat winH = METRICS_WIN_MIN_HEIGHT;
    CGFloat screenW = [screen visibleFrame].size.width;
    CGFloat screenH = [screen visibleFrame].size.height;
    CGFloat x = ([screen visibleFrame].origin.x
                 + (screenW - winW) / 2);
    CGFloat y = ([screen visibleFrame].origin.y
                 + (screenH - winH) / 2);

    return [self initWithContentRect: NSMakeRect(x, y, winW, winH)];
}

- (void) dealloc
{
    // NSLog(@"Eau: EauAlertPanel dealloc called for panel: %p", self);
    
    @try {
        // Stop any pending animations or callbacks
        [self setDefaultButtonCell: nil];
        [self setDelegate: nil];
    } @catch (id ex) {}

    // In ARC, ivars are automatically released when the object is deallocated
    // We don't need to explicitly release them, but we can set them to nil for safety
#if !__has_feature(objc_arc)
    /* Non-ARC builds (the Tests/ unit-test tool links this file directly)
       own the controls through their alloc/init here, so they must be
       released and NSWindow's dealloc must run; under ARC both happen
       implicitly when the ivar is zeroed. */
    [defButton release];
    [altButton release];
    [othButton release];
    [icoButton release];
    [titleField release];
    [messageField release];
    [scroll release];
#endif
    defButton = nil;
    altButton = nil;
    othButton = nil;
    icoButton = nil;
    titleField = nil;
    messageField = nil;
    scroll = nil;
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
    
    // NSLog(@"Eau: EauAlertPanel dealloc cleaning up completed");
    // In ARC, [super dealloc] is NOT called - it happens automatically
}

- (NSButton *) _makeButtonWithRect: (NSRect)rect tag: (NSInteger)tag
{
    NSButton *button = [[NSButton alloc] initWithFrame: rect];
    [button setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [button setButtonType: NSMomentaryPushInButton];
    [button setTitle: @""];
    [button setTarget: self];
    [button setAction: @selector(buttonAction:)];
    [button setTag: tag];
    [button setFont: [NSFont systemFontOfSize: 0]];
    NSDebugLog(@"Eau: Created button with tag %ld, target: %@, action: %@", tag, [button target], NSStringFromSelector([button action]));
    return button;
}

- (void) sizePanelToFit
{
    // NSLog(@"Eau: sizePanelToFit called");
    @try {
    NSRect bounds;
    NSSize ssize;
    NSSize bsize;
    NSSize wsize = {0.0, 0.0};
    NSScreen *screen;
    NSView *content;
    NSButton *buttons[3];
    float position = 0.0;
    int numberOfButtons;
    int i;
    BOOL needsScroll;
    BOOL couldNeedScroll;
    NSUInteger mask = [self styleMask];
    float textAreaWidth;
    float titleHeight = 0.0;
    float messageHeight = 0.0;
    
    screen = [self screen];
    if (screen == nil)
        screen = [NSScreen mainScreen];
    
    bounds = [screen frame];
    bounds = [NSWindow contentRectForFrameRect: bounds styleMask: mask];
    ssize = bounds.size;
    ssize.width = METRICS_SIZE_SCALE * ssize.width;
    ssize.height = METRICS_SIZE_SCALE_HEIGHT * ssize.height;
    
    // Start with minimum width
    wsize.width = METRICS_WIN_MIN_WIDTH;
    textAreaWidth = wsize.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
    
    // Calculate title size
    if (useControl(titleField))
    {
        NSRect rect = [titleField frame];
        // Constrain title to available width and let it wrap if needed
        NSSize titleSize = [[titleField attributedStringValue]
                            boundingRectWithSize: NSMakeSize(textAreaWidth, 1e6)
                            options: NSStringDrawingUsesLineFragmentOrigin].size;
        titleHeight = titleSize.height;
        rect.size = titleSize;
        [titleField setFrame: rect];
    }
    
    // Count buttons and calculate button area size
    bsize.width = METRICS_BUTTON_MIN_WIDTH;
    bsize.height = METRICS_BUTTON_HEIGHT;
    buttons[0] = defButton;
    buttons[1] = altButton;
    buttons[2] = othButton;
    numberOfButtons = 0;
    
    for (i = 0; i < 3; i++)
    {
        if (useControl(buttons[i]))
        {
            NSRect rect = [buttons[i] frame];
            if (bsize.width < rect.size.width)
                bsize.width = rect.size.width;
            if (bsize.height < rect.size.height)
                bsize.height = rect.size.height;
            numberOfButtons++;
        }
    }
    
    // Message field sizing with word wrap
    needsScroll = NO;
    couldNeedScroll = useControl(messageField);
    if (couldNeedScroll)
    {
        NSRect rect = [messageField frame];
        // Calculate message size with wrapping
        NSSize msgSize = [[messageField attributedStringValue]
                          boundingRectWithSize: NSMakeSize(textAreaWidth, 1e6)
                          options: NSStringDrawingUsesLineFragmentOrigin].size;
        messageHeight = msgSize.height;
        rect.size = msgSize;
        [messageField setFrame: rect];
    }
    
    // Calculate total height needed
    // Top margin + title + gap + message + gap to buttons + buttons + bottom margin
    float textContentHeight = METRICS_CONTENT_TOP_MARGIN + titleHeight;
    if (messageHeight > 0)
    {
        textContentHeight += METRICS_TITLE_MESSAGE_GAP + messageHeight;
    }
    textContentHeight += METRICS_CONTENT_BOTTOM_MARGIN;
    
    if (numberOfButtons > 0)
    {
        textContentHeight += bsize.height + METRICS_CONTENT_BOTTOM_MARGIN;
    }
    
    // Ensure icon has enough space (icon height + margins)
    float iconContentHeight = METRICS_ICON_TOP + METRICS_ICON_SIDE + METRICS_CONTENT_BOTTOM_MARGIN;
    if (numberOfButtons > 0)
    {
        iconContentHeight += bsize.height + METRICS_CONTENT_BOTTOM_MARGIN;
    }
    
    wsize.height = (textContentHeight > iconContentHeight) ? textContentHeight : iconContentHeight;
    
    // Resize window if message is too long
    if (ssize.height < wsize.height)
    {
        wsize.height = ssize.height;
        needsScroll = couldNeedScroll;
    }
    else if (wsize.height < METRICS_WIN_MIN_HEIGHT)
    {
        wsize.height = METRICS_WIN_MIN_HEIGHT;
    }
    
    if (needsScroll)
        wsize.width += [NSScroller scrollerWidth] + 4.0;
    
    if (ssize.width < wsize.width)
        wsize.width = ssize.width;
    else if (wsize.width < METRICS_WIN_MIN_WIDTH)
        wsize.width = METRICS_WIN_MIN_WIDTH;

    /* Whole pixels only (the height cap is a fraction of the screen):
       scrolling copies the visible text, and at a fractional offset cairo
       resamples it, so the text blurs a little more with every scroll step. */
    wsize.width = floor(wsize.width);
    wsize.height = floor(wsize.height);

    bounds = NSMakeRect(0, 0, wsize.width, wsize.height);
    bounds = [NSWindow frameRectForContentRect: bounds styleMask: mask];
    [self setMaxSize: bounds.size];
    [self setMinSize: bounds.size];
    [self setContentSize: wsize];
    content = [self contentView];
    bounds = [content bounds];
    
    // Place icon at top left
    if (useControl(icoButton))
    {
        NSRect iconRect = NSMakeRect(METRICS_ICON_LEFT,
                                      bounds.size.height - METRICS_ICON_TOP - METRICS_ICON_SIDE,
                                      METRICS_ICON_SIDE, METRICS_ICON_SIDE);
        [icoButton setFrame: iconRect];
    }
    
    // Place buttons at bottom right
    if (numberOfButtons > 0)
    {
        position = bounds.origin.x + bounds.size.width - METRICS_CONTENT_SIDE_MARGIN;
        for (i = 0; i < 3; i++)
        {
            if (useControl(buttons[i]))
            {
                NSRect rect;
                position -= bsize.width;
                rect.origin.x = position;
                rect.origin.y = bounds.origin.y + METRICS_CONTENT_BOTTOM_MARGIN;
                rect.size.width = bsize.width;
                rect.size.height = bsize.height;
                [buttons[i] setFrame: rect];
                position -= METRICS_BUTTON_VERT_INTERSPACE;
            }
        }
    }
    
    // Calculate vertical positions for title and message
    float buttonAreaHeight = (numberOfButtons > 0) ? (METRICS_CONTENT_BOTTOM_MARGIN + bsize.height) : 0;
    
    // Place title at top, left-aligned with TextLeft
    float currentY = bounds.size.height - METRICS_CONTENT_TOP_MARGIN;
    if (useControl(titleField))
    {
        NSRect trect = [titleField frame];
        trect.origin.x = METRICS_TEXT_LEFT;
        trect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
        currentY -= trect.size.height;
        trect.origin.y = currentY;
        [titleField setFrame: trect];
    }
    
    // Place message below title, same left alignment
    if (useControl(messageField))
    {
        NSRect mrect = [messageField frame];
        
        if (needsScroll)
        {
            NSRect srect;
            float width;
            
            /* The title height is measured text, so snap the text area's
               edges to whole pixels as well (see the window size above). */
            srect.origin.x = METRICS_TEXT_LEFT;
            srect.origin.y = ceil(buttonAreaHeight + METRICS_CONTENT_BOTTOM_MARGIN);
            srect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
            srect.size.height = floor(currentY - METRICS_TITLE_MESSAGE_GAP) - srect.origin.y;
            [scroll setFrame: srect];
            
            if (!useControl(scroll))
                [content addSubview: scroll];
            
            /* Clear the clip view's document pointer FIRST: NSClipView
               setDocumentView: early-returns when handed the same pointer,
               so re-attaching after removeFromSuperview would be a silent
               no-op and leave the scrolled variant empty on the second
               sizePanelToFit pass (runModal always lays out twice). */
            if ([scroll documentView] != nil)
                [scroll setDocumentView: nil];
            width = [NSScrollView contentSizeForFrameSize: srect.size
                                    hasHorizontalScroller: NO
                                      hasVerticalScroller: YES
                                               borderType: [scroll borderType]].width;
            mrect.origin = NSZeroPoint;
            /* Fill the clip content width rather than hugging the longest
               line, so the scrolled variant reads as a proper text area;
               only the height comes from the measurement. */
            mrect.size.width = width;
            mrect.size.height =
                [[messageField attributedStringValue]
                 boundingRectWithSize: NSMakeSize(width, 1e6)
                 options: NSStringDrawingUsesLineFragmentOrigin].size.height;
            [messageField setFrame: mrect];
            [scroll setDocumentView: messageField];
        }
        else
        {
            currentY -= METRICS_TITLE_MESSAGE_GAP;
            mrect.origin.x = METRICS_TEXT_LEFT;
            mrect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
            currentY -= mrect.size.height;
            mrect.origin.y = currentY;
            [messageField setFrame: mrect];
        }
    }
    else if (useControl(scroll))
    {
        [scroll removeFromSuperview];
    }
    
    isGreen = NO;
    // NSLog(@"Eau: sizePanelToFit displaying content");
    [content display];
    // NSLog(@"Eau: sizePanelToFit completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in sizePanelToFit: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

- (void) buttonAction: (id)sender
{
    BOOL stopping = eauAlertIsStopping(self);
    // NSLog(@"Eau: buttonAction called, sender: %@, stopping: %d", sender, stopping);
    if (sender == nil)
    {
        NSLog(@"Eau: WARNING - buttonAction called with nil sender");
        return;
    }

    // Prevent re-entrant calls while stopping modal
    if (stopping)
    {
        NSLog(@"Eau: WARNING - buttonAction called while already stopping modal, ignoring");
        return;
    }

    NSInteger tag = [sender tag];
    // NSLog(@"Eau: buttonAction tag: %ld", tag);
    if (![self isActivePanel])
    {
        NSLog(@"Eau: WARNING - buttonAction called when not in modal loop");
        return;
    }

    result = tag;
    eauAlertSetStopping(self, YES);

    // NSLog(@"Eau: buttonAction will stop modal with result: %ld", result);

    // Defer stopping the modal to the next run loop iteration.
    // We use performSelector with specific modes because dispatch_async to the
    // main queue may not execute while the run loop is in NSModalPanelRunLoopMode.
    // NSEventTrackingRunLoopMode must be included: only the scrolled variant
    // has a live scroller, and a stop requested while its thumb is being
    // dragged would otherwise wait until that tracking loop ends - which, in
    // an app that hangs mid-drag, is forever, leaving the dialog uncloseable.
    [self performSelector: @selector(_stopModalDeferred)
               withObject: nil
               afterDelay: 0.0
                  inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                                                      NSModalPanelRunLoopMode,
                                                      NSEventTrackingRunLoopMode,
                                                      nil]];

    // NSLog(@"Eau: buttonAction scheduled deferred modal stop");
}

- (void) _stopModalDeferred
{
    // Ensure we check isActivePanel to avoid stopping a context we don't own anymore
    if ([self isActivePanel] || [NSApp modalWindow] == self) {
        // NSLog(@"Eau: _stopModalDeferred executing for result: %ld", result);
        [NSApp stopModalWithCode: result];
    } else {
        // NSLog(@"Eau: _stopModalDeferred skipped - panel no longer active");
    }
    eauAlertSetStopping(self, NO);
}

- (NSInteger) result
{
    return result;
}

- (NSButton *) defaultButton
{
    return defButton;
}

- (BOOL) isActivePanel
{
    return [NSApp modalWindow] == self;
}

/* The titlebar close button must always be able to dismiss the dialog,
 * including the scrolled long-text variant while a wedged app is stuck in
 * scroller event tracking: ending the modal session here does not depend on
 * the WillClose observer or on buttonAction having been reached. */
- (BOOL) windowShouldClose: (id)sender
{
    @try {
        if ([NSApp modalWindow] == self)
            [NSApp abortModal];
    }
    @catch (id ex) {}
    return YES;
}

- (NSInteger) runModal
{
    /* Print the full dialog text (title and message) so CI logs show exactly
     * why a modal alert is up; the test suite treats an unhandled modal as a
     * failure, so the reason must be greppable from the log. */
    {
        NSString *ttl = titleField ? [titleField stringValue] : @"";
        NSString *msg = messageField ? [messageField stringValue] : @"";
        NSLog(@"Eau: EauAlertPanel runModal — title=\"%@\" message=\"%@\"", ttl, msg);
    }
    
    // Beep when alert is displayed (diagnostics)
    NSApplication *app = [NSApplication sharedApplication];
    // NSLog(@"Eau: EauAlertPanel about to beep - NSApp class: %@ respondsToSelector: %d",
    //       NSStringFromClass([app class]), (int)[app respondsToSelector:@selector(beep)]);
    if ([app respondsToSelector:@selector(beep)]) {
        [app performSelector:@selector(beep)];
    } else {
        // NSLog(@"Eau: NSApp does not respond to -beep");
    }
    
    @try {
        // Bail out if no text was set (initialized but unused panel).
        // GershwinBehaviors suppresses empty NSAlerts, but the legacy
        // NSRunAlertPanel family calls this method directly, so the panel
        // has to guard itself as well.
        NSString *title = titleField ? [[titleField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        NSString *msg = messageField ? [[messageField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] : @"";
        if (([title length] == 0) && ([msg length] == 0))
          {
            NSLog(@"Eau: EauAlertPanel runModal suppressed — title and message are empty/whitespace (probably a bug in the application)");
            return NSAlertErrorReturn;
          }

        if (isGreen)
        {
            // NSLog(@"Eau: EauAlertPanel calling sizePanelToFit");
            [self sizePanelToFit];
            // NSLog(@"Eau: EauAlertPanel sizePanelToFit completed");
        }
    
        // NSLog(@"[EauTrace] EauAlertPanel runModal: BEFORE center frame=%@ OSorigin=(%.0f,%.0f) size=(%.0f,%.0f)",
        //       NSStringFromRect([self frame]),
        //       [self frame].origin.x, [self frame].origin.y,
        //       [self frame].size.width, [self frame].size.height);
    
    // Ensure we're the key window and can handle events
    [self center];
    
        // NSLog(@"[EauTrace] EauAlertPanel runModal: AFTER center frame=%@ OSorigin=(%.0f,%.0f) size=(%.0f,%.0f)",
        //       NSStringFromRect([self frame]),
        //       [self frame].origin.x, [self frame].origin.y,
        //       [self frame].size.width, [self frame].size.height);
    
    // Float above all other windows (alert takes priority)
    [self setLevel: NSScreenSaverWindowLevel];

    // Raise the window to ensure it gets input focus
    [NSApp activateIgnoringOtherApps: YES];
    [self orderFrontRegardless];
        // NSLog(@"[EauTrace] EauAlertPanel runModal: AFTER orderFrontRegardless frame=%@",
        //       NSStringFromRect([self frame]));
    [self makeKeyAndOrderFront: self];
    
    // Make sure the default button has focus for Enter key handling
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
    }
    
    NSDebugLog(@"Eau: runModal - window is key: %d", [self isKeyWindow]);
    NSDebugLog(@"Eau: runModal - first responder: %@", [self firstResponder]);
    
    // NSLog(@"Eau: About to call runModalForWindow");
    __block id closeObs = [[NSNotificationCenter defaultCenter]
      addObserverForName: NSWindowWillCloseNotification
      object: self queue: nil usingBlock: ^(NSNotification *note) {
        /* The close button must end the modal session even if the app is
         * wedged; never let an exception here leave the dialog up. */
        @try {
          [NSApp abortModal];
        } @catch (id ex) {}
      }];
    result = [NSApp runModalForWindow: self];
    [[NSNotificationCenter defaultCenter] removeObserver: closeObs];
    // NSLog(@"Eau: runModalForWindow returned with result: %ld", result);
    [self orderOut: self];
    // NSLog(@"Eau: EauAlertPanel runModal completed");
    return result;
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in EauAlertPanel runModal: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
        return NSAlertErrorReturn;
    }
}

/* The panel's keyboard handling (Return/Space/Esc, Tab and arrow focus
 * cycling, Cmd-C) stays here rather than in GershwinBehaviors: it is made of
 * overrides on this NSPanel subclass driven by its own button ivars, and
 * GSAlertPanel instances are morphed into this class, so a behavior-bundle
 * swizzle on GSAlertPanel would never see them.
 * TODO: Upstream to GNUstep - GSAlertPanel should map Esc to a Cancel button
 * and cycle focus between its buttons itself. */
- (void) keyDown: (NSEvent *)event
{
    NSString *chars = [event characters];
    NSDebugLog(@"Eau: keyDown received: '%@'", chars);
    if ([chars length] > 0)
    {
        unichar keyChar = [chars characterAtIndex: 0];
    
    // Handle Enter/Return for default button
    if (keyChar == '\r' && useControl(defButton))
    {
        NSDebugLog(@"Eau: keyDown Enter pressed, clicking default button");
        [self buttonAction: defButton];
        return;
    }
    
    // Handle Spacebar to activate focused button
    if (keyChar == ' ')
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton && useControl(defButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
        }
        else if (current == altButton && useControl(altButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking alternate button");
            [self buttonAction: altButton];
        }
        else if (current == othButton && useControl(othButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking other button");
            [self buttonAction: othButton];
        }
        else if (useControl(defButton))
        {
            // NSLog(@"Eau: keyDown Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
        }
        return;
    }
    
    // Handle Escape for Cancel button
    if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
    {
        [self buttonAction: altButton];
        return;
    }
    
    // Handle Tab to cycle through buttons
    if (keyChar == '\t')
    {
        NSView *current = (NSView *)[self firstResponder];
        NSView *next = [current nextKeyView];
        if (next != nil)
        {
            [self makeFirstResponder: next];
        }
        else if (useControl(defButton))
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Shift-Tab to cycle backwards
    if (([event modifierFlags] & NSShiftKeyMask) && keyChar == '\t')
    {
        NSView *current = (NSView *)[self firstResponder];
        NSView *prev = [current previousKeyView];
        if (prev != nil)
        {
            [self makeFirstResponder: prev];
        }
        else if (useControl(othButton))
        {
            [self makeFirstResponder: othButton];
        }
        else if (useControl(altButton))
        {
            [self makeFirstResponder: altButton];
        }
        else if (useControl(defButton))
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Right Arrow to cycle forward through buttons
    if (keyChar == NSRightArrowFunctionKey && (([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == 0))
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton)
        {
            if (useControl(altButton))
                [self makeFirstResponder: altButton];
            else if (useControl(othButton))
                [self makeFirstResponder: othButton];
        }
        else if (current == altButton)
        {
            if (useControl(othButton))
                [self makeFirstResponder: othButton];
            else
                [self makeFirstResponder: defButton];
        }
        else if (current == othButton)
        {
            [self makeFirstResponder: defButton];
        }
        return;
    }
    
    // Handle Left Arrow to cycle backward through buttons
    if (keyChar == NSLeftArrowFunctionKey && (([event modifierFlags] & (NSShiftKeyMask | NSCommandKeyMask | NSAlternateKeyMask | NSControlKeyMask)) == 0))
    {
        NSView *current = (NSView *)[self firstResponder];
        if (current == defButton)
        {
            if (useControl(othButton))
                [self makeFirstResponder: othButton];
            else if (useControl(altButton))
                [self makeFirstResponder: altButton];
        }
        else if (current == altButton)
        {
            [self makeFirstResponder: defButton];
        }
        else if (current == othButton)
        {
            if (useControl(altButton))
                [self makeFirstResponder: altButton];
            else if (useControl(defButton))
                [self makeFirstResponder: defButton];
        }
        return;
    }
    }
    
    [super keyDown: event];
}

- (void) copyAllTextToPasteboard
{
    NSMutableArray *parts = [NSMutableArray array];
    NSString *winTitle = [self title];
    if ([winTitle length] > 0)
    {
        [parts addObject: winTitle];
    }
    if (useControl(titleField))
    {
        NSString *t = [titleField stringValue];
        if ([t length] > 0)
        {
            [parts addObject: t];
        }
    }
    if (useControl(messageField))
    {
        NSString *m = [messageField stringValue];
        if ([m length] > 0)
        {
            [parts addObject: m];
        }
    }
    NSMutableArray *btnLabels = [NSMutableArray array];
    if (useControl(defButton))
    {
        [btnLabels addObject: [defButton title]];
    }
    if (useControl(altButton))
    {
        [btnLabels addObject: [altButton title]];
    }
    if (useControl(othButton))
    {
        [btnLabels addObject: [othButton title]];
    }
    if ([btnLabels count] > 0)
    {
        [parts addObject: [btnLabels componentsJoinedByString: @"    "]];
    }
    if ([parts count] == 0)
    {
        return;
    }
    NSString *summary = [parts componentsJoinedByString: @"\n"];
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes: [NSArray arrayWithObject: NSPasteboardTypeString]
               owner: nil];
    [pb setString: summary forType: NSPasteboardTypeString];
    NSDebugLog(@"Eau: Copied dialog text to pasteboard: %@", summary);
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
    NSString *chars = [event characters];
    NSUInteger modifiers = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;
    // NSLog(@"Eau: performKeyEquivalent received: '%@', modifiers: %lu, isActivePanel: %d", chars, (unsigned long)modifiers, [self isActivePanel]);

    // During modal operation, intercept ALL keyboard events to prevent app shortcuts
    if ([self isActivePanel])
    {
        // Handle Cmd-C (Alt-C on GNUstep) to copy all dialog text to clipboard
        if ((modifiers & NSCommandKeyMask) && [chars caseInsensitiveCompare: @"c"] == NSOrderedSame)
        {
            // NSLog(@"Eau: performKeyEquivalent Cmd-C pressed, copying dialog text");
            [self copyAllTextToPasteboard];
            return YES;
        }

        // Handle Return/Enter for default button
        if ([chars isEqualToString: @"\r"] && useControl(defButton))
        {
            // NSLog(@"Eau: performKeyEquivalent Enter pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }

        // Handle Spacebar for default button
        if ([chars isEqualToString: @" "] && modifiers == 0 && useControl(defButton))
        {
            // NSLog(@"Eau: performKeyEquivalent Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }

        // Handle Escape for cancel button
        if ([chars isEqualToString: @"\e"] && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
        {
            // NSLog(@"Eau: performKeyEquivalent Escape pressed, clicking cancel button");
            [self buttonAction: altButton];
            return YES;
        }

        // Let unhandled events (Tab, arrow keys) propagate to keyDown:
        return NO;
    }

    return [super performKeyEquivalent: event];
}

- (void) sendEvent: (NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString *chars = [event characters];
        // NSLog(@"Eau: sendEvent received keyDown: '%@', isActivePanel: %d", chars, [self isActivePanel]);
        
        // CRITICAL: During modal operation, try performKeyEquivalent FIRST
        // This ensures keyboard events are handled by the dialog, not the app
        if ([self isActivePanel])
        {
            if ([self performKeyEquivalent: event])
            {
                // NSLog(@"Eau: Event consumed by performKeyEquivalent, not propagating to app");
                return;  // Event was handled, DO NOT call super or keyDown
            }
        }
        
        // Always handle keyboard events ourselves - prevent app shortcuts from stealing them
        if ([chars length] > 0)
        {
            unichar keyChar = [chars characterAtIndex: 0];
            
            // Handle Return/Enter for default button
            if (keyChar == '\r' && useControl(defButton))
            {
                // NSLog(@"Eau: sendEvent Enter pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Spacebar for default button
            if (keyChar == ' ' && useControl(defButton))
            {
                // NSLog(@"Eau: sendEvent Spacebar pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Escape for cancel button
            if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
            {
                // NSLog(@"Eau: sendEvent Escape pressed, clicking cancel button");
                [self buttonAction: altButton];
                return;  // Don't call super - we handled it
            }
        }
    }
    [super sendEvent: event];
}

/* Ensure the window is centered right before it is ordered front.
   This prevents a visual flash where the X window would otherwise be
   created at the OS (0,0) position (near bottom-left of the screen)
   before being moved to the correct center position by -center. */
- (void) orderFrontRegardless
{
    /* Non-modal alert: print its text so CI logs show why it appeared. */
    {
        NSString *ttl = titleField ? [titleField stringValue] : @"";
        NSString *msg = messageField ? [messageField stringValue] : @"";
        NSLog(@"Eau: EauAlertPanel shown non-modally — title=\"%@\" message=\"%@\"", ttl, msg);
    }
    [self center];
    [super orderFrontRegardless];
}

- (BOOL) canBecomeKeyWindow
{
    return YES;
}

- (BOOL) canBecomeMainWindow
{
    return YES;
}

/* GSExceptionPanel calls setUserInfo: on the panel after morphing it to
   EauAlertPanel via object_setClass().  Store the userInfo via an
   associated object to avoid adding an ivar. */
static const void *kEAUUserInfoKey = &kEAUUserInfoKey;

- (void) setUserInfo: (NSDictionary *)userInfo
{
    objc_setAssociatedObject(self, kEAUUserInfoKey, userInfo,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id) userInfo
{
    return objc_getAssociatedObject(self, kEAUUserInfoKey);
}

/* GSExceptionPanel calls userInfoPanel on the morphed panel to order it out. */
- (id) userInfoPanel
{
    return self;
}

- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
{
    // NSLog(@"Eau: setTitleBar called with title='%@', message='%@'", title, message);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil");
        return;
    }
    
    // NSLog(@"Eau: Setting window title");
    if (titleBar != nil)
        [self setTitle: titleBar];
    
    // NSLog(@"Eau: Setting icon");
    [icoButton setTitle: @""];   // Guard: never show the default "Button" text
    [icoButton setImagePosition: NSImageOnly];
    if (icon != nil)
        [icoButton setImage: icon];
    
    if (title == nil)
        title = titleBar;
    
    // NSLog(@"Eau: Setting title field");
    setControl(content, titleField, title);
    
    // NSLog(@"Eau: Handling scroll view");
    if (useControl(scroll))
    {
        [scroll setDocumentView: nil];
        [scroll removeFromSuperview];
        [messageField removeFromSuperview];
    }
    
    // NSLog(@"Eau: Setting message field");
    setControl(content, messageField, message);
    
    // Always use left alignment for consistent appearance
    [messageField setAlignment: NSLeftTextAlignment];
    
    // NSLog(@"Eau: setTitleBar completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
                 def: (NSString *)defaultButton
                 alt: (NSString *)alternateButton
               other: (NSString *)otherButton
{
    NSView *content = [self contentView];
    
    [self setTitleBar: titleBar icon: icon title: title message: message];
    setControl(content, defButton, defaultButton);
    setControl(content, altButton, alternateButton);
    setControl(content, othButton, otherButton);
    
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
        // Set the default button cell to enable blue pulsing animation
        [self setDefaultButtonCell: [defButton cell]];
    }
    else
        [self makeFirstResponder: self];
    
    if (useControl(altButton))
        setKeyEquivalent(altButton);
    if (useControl(othButton))
        setKeyEquivalent(othButton);
    
    // Set up key view chain
    {
        BOOL ud = useControl(defButton);
        BOOL ua = useControl(altButton);
        BOOL uo = useControl(othButton);
        
        if (ud)
        {
            if (uo)
                [defButton setNextKeyView: othButton];
            else if (ua)
                [defButton setNextKeyView: altButton];
            else
            {
                [defButton setPreviousKeyView: nil];
                [defButton setNextKeyView: nil];
            }
        }
        
        if (uo)
        {
            if (ua)
                [othButton setNextKeyView: altButton];
            else if (ud)
                [othButton setNextKeyView: defButton];
            else
            {
                [othButton setPreviousKeyView: nil];
                [othButton setNextKeyView: nil];
            }
        }
        
        if (ua)
        {
            if (ud)
                [altButton setNextKeyView: defButton];
            else if (uo)
                [altButton setNextKeyView: othButton];
            else
            {
                [altButton setPreviousKeyView: nil];
                [altButton setNextKeyView: nil];
            }
        }
    }
    
    [self sizePanelToFit];
    isGreen = YES;
    result = NSAlertErrorReturn;
}

- (void) setButtons: (NSArray *)buttons
{
    // NSLog(@"Eau: setButtons called with %lu buttons", (unsigned long)[buttons count]);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil in setButtons");
        return;
    }
    NSUInteger count = [buttons count];
    
    // NSLog(@"Eau: Setting button 0");
    setButton(content, defButton, count > 0 ? [buttons objectAtIndex: 0] : nil);
    // NSLog(@"Eau: Setting button 1");
    setButton(content, altButton, count > 1 ? [buttons objectAtIndex: 1] : nil);
    // NSLog(@"Eau: Setting button 2");
    setButton(content, othButton, count > 2 ? [buttons objectAtIndex: 2] : nil);
    
    // NSLog(@"Eau: Setting up first responder");
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
        // Set the default button cell to enable blue pulsing animation
        [self setDefaultButtonCell: [defButton cell]];
    }
    else
        [self makeFirstResponder: self];
    
    // NSLog(@"Eau: Setting up key view chain");
    if (count > 2)
    {
        [defButton setNextKeyView: othButton];
        [othButton setNextKeyView: altButton];
        [altButton setNextKeyView: defButton];
    }
    else if (count > 1)
    {
        [defButton setNextKeyView: altButton];
        [altButton setNextKeyView: defButton];
    }
    else if (count > 0)
    {
        [defButton setPreviousKeyView: nil];
        [defButton setNextKeyView: nil];
    }
    
    // NSLog(@"Eau: Calling sizePanelToFit from setButtons");
    [self sizePanelToFit];
    // NSLog(@"Eau: sizePanelToFit completed from setButtons");
    isGreen = YES;
    result = NSAlertErrorReturn;
    // NSLog(@"Eau: setButtons completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

@end

#pragma mark - Helper Functions

static NSScrollView *makeScrollViewWithRect(NSRect rect)
{
    float lineHeight = [METRICS_FONT_SYSTEM_REGULAR_11 boundingRectForFont].size.height;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame: rect];
    
    [scrollView setBorderType: NSLineBorder];
    [scrollView setBackgroundColor: [NSColor controlBackgroundColor]];
    [scrollView setHasHorizontalScroller: NO];
    [scrollView setHasVerticalScroller: YES];
    [scrollView setScrollsDynamically: YES];
    [scrollView setLineScroll: lineHeight];
    [scrollView setPageScroll: lineHeight * 10.0];
    return scrollView;
}

static void setControl(NSView *content, id control, NSString *title)
{
    if (title != nil)
    {
        if ([control respondsToSelector: @selector(setTitle:)])
            [control setTitle: title];
        else if ([control respondsToSelector: @selector(setStringValue:)])
            [control setStringValue: title];
        [control sizeToFit];
        if (!useControl(control))
            [content addSubview: control];
    }
    else if (useControl(control))
    {
        [control removeFromSuperview];
    }
}

static void setButton(NSView *content, NSButton *control, NSButton *templateBtn)
{
    if (templateBtn != nil)
    {
        [control setTitle: [templateBtn title]];
        [control setKeyEquivalent: [templateBtn keyEquivalent]];
        [control setKeyEquivalentModifierMask: [templateBtn keyEquivalentModifierMask]];
        [control setTag: [templateBtn tag]];
        [control sizeToFit];
        if (!useControl(control))
            [content addSubview: control];
    }
    else if (useControl(control))
    {
        [control removeFromSuperview];
    }
}

static void setKeyEquivalent(NSButton *button)
{
    NSString *title = [button title];
    
    if (![[button keyEquivalent] isEqualToString: @"\r"])
    {
        if ([title isEqualToString: @"Cancel"])
        {
            [button setKeyEquivalent: @"\e"];
            [button setKeyEquivalentModifierMask: 0];
        }
        else if ([title isEqualToString: @"Don't Save"])
        {
            [button setKeyEquivalent: @"d"];
            [button setKeyEquivalentModifierMask: NSCommandKeyMask];
        }
        else
        {
            [button setKeyEquivalent: @""];
            [button setKeyEquivalentModifierMask: 0];
        }
    }
}

#pragma mark - NSAlert Category for Swizzling

/* NSAlert (Eau): builds the themed EauAlertPanel for NSAlert and for the
 * legacy NSRunAlertPanel family.  Running the alert modally (activation,
 * focus, teardown) is theme-independent and lives in
 * GershwinBehaviors.bundle (Behaviors/NSAlert+GB.m), which hands an
 * EauAlertPanel back to us through -[Eau runModalForAlertPanel:result:]. */
@implementation NSAlert (Eau)

+ (void) load
{
    static BOOL didSwizzle = NO;
    if (didSwizzle)
        return;
    didSwizzle = YES;
    
    NSDebugLog(@"Eau: Installing NSAlert customizations");
    // // NSLog(@"Eau: Installing NSAlert customizations - FORCED LOG");
    
    // Swizzle NSAlert's _setupPanel to use EauAlertPanel
    Class alertClass = NSClassFromString(@"NSAlert");
    SEL origSetupSel = @selector(_setupPanel);
    SEL swizzledSetupSel = @selector(eau_setupPanel);
    
    // // NSLog(@"Eau: Found NSAlert class: %@", alertClass);
    
    Method origSetupMethod = class_getInstanceMethod(alertClass, origSetupSel);
    Method swizzledSetupMethod = class_getInstanceMethod(alertClass, swizzledSetupSel);
    
    // // NSLog(@"Eau: Original _setupPanel method: %p", origSetupMethod);
    // // NSLog(@"Eau: Swizzled eau_setupPanel method: %p", swizzledSetupMethod);
    
    if (origSetupMethod && swizzledSetupMethod)
    {
        BOOL didAdd = class_addMethod(alertClass,
                                      origSetupSel,
                                      method_getImplementation(swizzledSetupMethod),
                                      method_getTypeEncoding(swizzledSetupMethod));
        if (didAdd)
        {
            class_replaceMethod(alertClass,
                                swizzledSetupSel,
                                method_getImplementation(origSetupMethod),
                                method_getTypeEncoding(origSetupMethod));
        }
        else
        {
            method_exchangeImplementations(origSetupMethod, swizzledSetupMethod);
        }
        NSDebugLog(@"Eau: NSAlert _setupPanel swizzled successfully");
        // // NSLog(@"Eau: NSAlert _setupPanel swizzled successfully - FORCED LOG");
    }
    else
    {
        NSDebugLog(@"Eau: Warning - could not find _setupPanel method to swizzle");
        // // NSLog(@"Eau: Warning - could not find _setupPanel method to swizzle - FORCED LOG");
    }
    
    // Also swizzle GSAlertPanel's _initWithoutGModel to handle legacy alert functions
    // (NSRunAlertPanel, NSGetAlertPanel, etc.) which create GSAlertPanel directly
    Class gsAlertPanelClass = NSClassFromString(@"GSAlertPanel");
    if (gsAlertPanelClass)
    {
        SEL origInitSel = @selector(_initWithoutGModel);
        SEL swizzledInitSel = @selector(eau_initWithoutGModel);
        
        // Add the swizzled init method to GSAlertPanel dynamically
        Method initHelperMethod = class_getInstanceMethod([EauAlertPanel class], @selector(eau_initWithoutGModelHelper));
        if (initHelperMethod)
        {
            class_addMethod(gsAlertPanelClass,
                           swizzledInitSel,
                           method_getImplementation(initHelperMethod),
                           method_getTypeEncoding(initHelperMethod));
            
            Method origInitMethod = class_getInstanceMethod(gsAlertPanelClass, origInitSel);
            Method newSwizzledMethod = class_getInstanceMethod(gsAlertPanelClass, swizzledInitSel);
            
            if (origInitMethod && newSwizzledMethod)
            {
                method_exchangeImplementations(origInitMethod, newSwizzledMethod);
                NSDebugLog(@"Eau: GSAlertPanel _initWithoutGModel swizzled successfully");
            }
        }

        // Note: GSAlertPanel runModal/sizePanelToFit swizzles are intentionally
        // disabled here to avoid crashes in legacy alert panels.
    }
}

// Replacement for NSAlert's _setupPanel method
// Builds a themed EauAlertPanel and assigns it to NSAlert's _window ivar.
- (void) eau_setupPanel
{
    // NSLog(@"Eau: eau_setupPanel called for NSAlert");
    
    EauAlertPanel *panel;
    NSString *title;
    
    @try {
    // NSLog(@"Eau: Creating EauAlertPanel");
    panel = [[EauAlertPanel alloc] init];
    if (panel == nil)
    {
        NSLog(@"Eau: CRITICAL - EauAlertPanel init returned nil");
        return;
    }
    // NSLog(@"Eau: EauAlertPanel created successfully: %@", panel);
    
    // Access NSAlert's ivars through KVC or accessor methods
    // NSLog(@"Eau: Accessing NSAlert properties");
    NSAlertStyle style = NSWarningAlertStyle;
    NSString *messageText = nil;
    NSString *informativeText = nil;
    NSImage *icon = nil;
    NSArray *buttons = nil;
    
    @try {
        style = [self alertStyle];
        // NSLog(@"Eau: alertStyle: %ld", (long)style);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting alertStyle: %@", e);
    }
    
    @try {
        messageText = [self messageText];
        // NSLog(@"Eau: messageText: %@", messageText);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting messageText: %@", e);
    }
    
    @try {
        informativeText = [self informativeText];
        // NSLog(@"Eau: informativeText: %@", informativeText);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting informativeText: %@", e);
    }
    
    @try {
        icon = [self icon];
        // NSLog(@"Eau: icon: %@", icon);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting icon: %@", e);
    }
    
    @try {
        buttons = [self buttons];
        // NSLog(@"Eau: buttons count: %lu", (unsigned long)[buttons count]);
    } @catch (NSException *e) {
        // NSLog(@"Eau: Exception getting buttons: %@", e);
    }
    
    // Set default icons based on alert style if no custom icon is provided
    if (icon == nil)
    {
        // NSLog(@"Eau: No icon provided, using default for style %ld", (long)style);
        @try {
            switch (style)
            {
                case NSCriticalAlertStyle:
                    icon = [NSImage imageNamed: @"GSStop"];
                    break;
                case NSInformationalAlertStyle:
                    // No default icon for informational alerts
                    break;
                case NSWarningAlertStyle:
                default:
                    icon = [NSImage imageNamed: @"NSCaution"];
                    break;
            }
            // if (icon != nil)
            //     NSLog(@"Eau: Loaded default icon: %@", icon);
        } @catch (NSException *e) {
            // NSLog(@"Eau: Exception loading default icon: %@", e);
        }
    }
    
    switch (style)
    {
        case NSCriticalAlertStyle:
            title = @"";
            break;
        case NSInformationalAlertStyle:
            title = @"";
            break;
        case NSWarningAlertStyle:
        default:
            title = @"";
            break;
    }
    
    if (messageText == nil) {
        NSLog(@"Eau: NSAlert with nil messageText (title will be \"Alert\") — informativeText=%@, self=%@",
              informativeText, self);
    }
    @try {
        [panel setTitleBar: title
                      icon: icon
                     title: messageText != nil ? messageText : @"Alert"
                   message: informativeText != nil ? informativeText : @""];
        // NSLog(@"Eau: setTitleBar completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", e);
    }
    
    @try {
        if ([buttons count] == 0)
        {
            // NSLog(@"Eau: No buttons, adding default OK button");
            [self addButtonWithTitle: @"OK"];
            buttons = [self buttons];
        }
        
        // NSLog(@"Eau: Setting %lu buttons on panel", (unsigned long)[buttons count]);
        [panel setButtons: buttons];
        // NSLog(@"Eau: setButtons completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", e);
    }
    
    // Set the _window ivar directly when possible to avoid KVC retain/release side effects
    // NSLog(@"Eau: Setting _window ivar on NSAlert");
    {
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            object_setIvar(self, windowIvar, panel);
            objc_setAssociatedObject(self, kEAUAlertWindowRetainKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            // NSLog(@"Eau: Successfully set _window via ivar");
        }
        else
        {
            @try {
                [self setValue: panel forKey: @"_window"];
                // NSLog(@"Eau: Successfully set _window via KVC");
            }
            @catch (NSException *exception) {
                NSLog(@"Eau: CRITICAL - could not set _window ivar on NSAlert: %@", exception);
            }
        }
    }
    
    // NSLog(@"Eau: eau_setupPanel completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: FATAL EXCEPTION in eau_setupPanel: %@", exception);
        // NSLog(@"Eau: Exception reason: %@", [exception reason]);
        // NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

@end
