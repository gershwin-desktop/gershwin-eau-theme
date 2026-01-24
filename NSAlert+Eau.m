//
// NSAlert+Eau.m
//
// Comprehensive NSAlert customization for Eau theme.
// Replaces GSAlertPanel with EauAlertPanel for full control over appearance.
//

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
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

static id EAUGetAlertIvar(id obj, const char *name)
{
    Ivar ivar = class_getInstanceVariable([obj class], name);
    if (ivar == NULL)
    {
        return nil;
    }
    return object_getIvar(obj, ivar);
}

// Declare -beep on NSApplication so callers in this file don't warn at compile time
@interface NSApplication (EauBeep)
- (void)beep;
@end

// Private category to declare swizzled selectors so the compiler knows about them
@interface EauAlertPanel (Swizzles)
- (id)eau_initWithoutGModel;
- (id)eau_initWithoutGModelHelper __attribute__((objc_method_family(init)));
- (NSInteger)eau_runModal;
- (NSInteger)eau_runModalHelper;
- (NSButton *)eau_getDefButton;
@end

#pragma mark - EauAlertPanel Implementation

@implementation EauAlertPanel
{
    BOOL _isStoppingModal;
    id _selfRetainer;
}

static const void *kEAUAlertWindowRetainKey = &kEAUAlertWindowRetainKey;

+ (void) initialize
{
    if (self == [EauAlertPanel class])
    {
        [self setVersion: 1];
    }
}

- (id) initWithContentRect: (NSRect)rect
{
    NSLog(@"Eau: EauAlertPanel initWithContentRect called");
    self = [super initWithContentRect: rect
                            styleMask: NSTitledWindowMask
                              backing: NSBackingStoreRetained
                                defer: YES];
    if (self == nil)
    {
        NSLog(@"Eau: EauAlertPanel super init returned nil");
        return nil;
    }
    
    NSLog(@"Eau: EauAlertPanel setting properties");
    [self setTitle: @" "];
    [self setLevel: NSModalPanelWindowLevel];
    [self setHidesOnDeactivate: NO];
    [self setBecomesKeyOnlyIfNeeded: NO];
    
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
    // NSLog(@"Eau: defButton key equivalent set to: '%@' - FORCED LOG", [defButton keyEquivalent]);
    [defButton setHighlightsBy: NSPushInCellMask | NSChangeGrayCellMask | NSContentsCellMask];
    @try {
        [defButton setImagePosition: NSImageRight];
        [defButton setImage: [NSImage imageNamed: @"common_ret"]];
        [defButton setAlternateImage: [NSImage imageNamed: @"common_retH"]];
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception loading button images: %@", e);
    }
    [defButton setFont: titleFont];  // Mark as default with bold font
    
    altButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertAlternateReturn];
    othButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertOtherReturn];
    
    // Scroll view for long messages
    scroll = makeScrollViewWithRect(NSMakeRect(0, 0, 80, 80));
    
    result = NSAlertErrorReturn;
    isGreen = YES;
    _isStoppingModal = NO;
    
    NSLog(@"Eau: EauAlertPanel initWithContentRect completed successfully");
    return self;
}

- (id) init
{
    NSLog(@"Eau: EauAlertPanel init called");
    return [self initWithContentRect: NSMakeRect(0, 0, METRICS_WIN_MIN_WIDTH, METRICS_WIN_MIN_HEIGHT)];
}

// Helper method injected into GSAlertPanel via swizzling
// - Calls original _initWithoutGModel
// - Removes legacy separator line
// - Applies Eau fonts to match AppearanceMetrics
- (id) eau_initWithoutGModelHelper
{
    // Call the original implementation (which is now at this selector after swizzling)
    id panel = [self eau_initWithoutGModel];
    if (panel == nil)
        return nil;

    // Apply Eau fonts to legacy GSAlertPanel controls
    NSTextField *legacyTitleField = (NSTextField *)EAUGetAlertIvar(panel, "titleField");
    NSTextField *legacyMessageField = (NSTextField *)EAUGetAlertIvar(panel, "messageField");
    NSButton *legacyDefButton = (NSButton *)EAUGetAlertIvar(panel, "defButton");
    NSButton *legacyAltButton = (NSButton *)EAUGetAlertIvar(panel, "altButton");
    NSButton *legacyOthButton = (NSButton *)EAUGetAlertIvar(panel, "othButton");

    if (legacyTitleField != nil)
    {
        [legacyTitleField setFont: METRICS_FONT_SYSTEM_BOLD_13];
    }
    if (legacyMessageField != nil)
    {
        [legacyMessageField setFont: METRICS_FONT_SYSTEM_REGULAR_11];
    }
    if (legacyDefButton != nil)
    {
        [legacyDefButton setFont: METRICS_FONT_SYSTEM_BOLD_13];
        [legacyDefButton sizeToFit];
    }
    if (legacyAltButton != nil)
    {
        [legacyAltButton setFont: METRICS_FONT_SYSTEM_REGULAR_13];
        [legacyAltButton sizeToFit];
    }
    if (legacyOthButton != nil)
    {
        [legacyOthButton setFont: METRICS_FONT_SYSTEM_REGULAR_13];
        [legacyOthButton sizeToFit];
    }
    
    // Remove the horizontal line (NSBox with NSGrooveBorder)
    NSView *content = [(NSPanel *)panel contentView];
    NSArray *subviews = [[content subviews] copy];
    for (NSView *subview in subviews)
    {
        if ([subview isKindOfClass: [NSBox class]])
        {
            NSBox *box = (NSBox *)subview;
            // The line has NSGrooveBorder and is very thin (height <= 3)
            if ([box borderType] == NSGrooveBorder && [box frame].size.height <= 3.0)
            {
                [box removeFromSuperview];
                EAULOG(@"Eau: Removed horizontal line from GSAlertPanel");
            }
        }
    }
    return panel;
}

// Helper method to get the default button from GSAlertPanel
// GSAlertPanel has an ivar 'defButton' that we need to access
- (NSButton *) eau_getDefButton
{
    // Try to access the defButton ivar
    Ivar defButtonIvar = class_getInstanceVariable([self class], "defButton");
    if (defButtonIvar)
    {
        return object_getIvar(self, defButtonIvar);
    }
    return nil;
}

// Helper method that will be injected into GSAlertPanel's runModal
// This ensures focus and pulsing work for legacy alert panels
- (NSInteger) eau_runModalHelper
{
    EAULOG(@"Eau: eau_runModalHelper called for GSAlertPanel");
    
    // Get the default button from the ivar
    NSButton *defBtn = [self eau_getDefButton];
    
    // Raise the window to ensure it gets input focus
    [NSApp activateIgnoringOtherApps: YES];
    [(NSPanel *)self orderFrontRegardless];
    [(NSPanel *)self makeKeyAndOrderFront: self];
    
    // Ensure the default button has focus and pulsing
    if (defBtn && [[defBtn superview] superview] != nil)
    {
        [(NSPanel *)self makeFirstResponder: defBtn];
        // Set default button cell to enable pulsing animation
        [(NSPanel *)self setDefaultButtonCell: [defBtn cell]];
        EAULOG(@"Eau: GSAlertPanel set default button focus and pulsing for button: %@", defBtn);
    }
    
    // Call the original runModal implementation
    return [self eau_runModal];
}

- (void) dealloc
{
    NSLog(@"Eau: EauAlertPanel dealloc called for panel: %@", self);
    
    // In ARC, ivars are automatically released when the object is deallocated
    // We don't need to explicitly release them, but we can set them to nil for safety
    defButton = nil;
    altButton = nil;
    othButton = nil;
    icoButton = nil;
    titleField = nil;
    messageField = nil;
    scroll = nil;
    
    NSLog(@"Eau: EauAlertPanel dealloc cleaning up completed");
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
    EAULOG(@"Eau: Created button with tag %ld, target: %@, action: %@", tag, [button target], NSStringFromSelector([button action]));
    return button;
}

- (void) sizePanelToFit
{
    NSLog(@"Eau: sizePanelToFit called");
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
    ssize.height = METRICS_SIZE_SCALE * ssize.height;
    
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
            
            srect.origin.x = METRICS_TEXT_LEFT;
            srect.origin.y = buttonAreaHeight + METRICS_CONTENT_BOTTOM_MARGIN;
            srect.size.width = bounds.size.width - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
            srect.size.height = currentY - METRICS_TITLE_MESSAGE_GAP - srect.origin.y;
            [scroll setFrame: srect];
            
            if (!useControl(scroll))
                [content addSubview: scroll];
            
            [messageField removeFromSuperview];
            width = [NSScrollView contentSizeForFrameSize: srect.size
                                    hasHorizontalScroller: NO
                                      hasVerticalScroller: YES
                                               borderType: [scroll borderType]].width;
            mrect.origin = NSZeroPoint;
            mrect.size = [[messageField attributedStringValue]
                          boundingRectWithSize: NSMakeSize(width, 1e6)
                          options: NSStringDrawingUsesLineFragmentOrigin].size;
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
    NSLog(@"Eau: sizePanelToFit displaying content");
    [content display];
    NSLog(@"Eau: sizePanelToFit completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in sizePanelToFit: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

- (void) buttonAction: (id)sender
{
    NSLog(@"Eau: buttonAction called, sender: %@, _isStoppingModal: %d", sender, _isStoppingModal);
    if (sender == nil)
    {
        NSLog(@"Eau: WARNING - buttonAction called with nil sender");
        return;
    }
    
    // Prevent re-entrant calls while stopping modal
    if (_isStoppingModal)
    {
        NSLog(@"Eau: WARNING - buttonAction called while already stopping modal, ignoring");
        return;
    }
    
    NSInteger tag = [sender tag];
    NSLog(@"Eau: buttonAction tag: %ld", tag);
    if (![self isActivePanel])
    {
        NSLog(@"Eau: WARNING - buttonAction called when not in modal loop");
        return;
    }
    
    result = tag;
    _isStoppingModal = YES;
    
    NSLog(@"Eau: buttonAction will stop modal with result: %ld", result);
    
    // CRITICAL FIX: Defer stopModal to next run loop iteration
    // This prevents crashes when performClick: is still processing events
    // The window must remain valid until all event handling completes
    // Use NSRunLoopCommonModes to work in both modal panel and default run loop modes
    _selfRetainer = self;
    [[NSRunLoop currentRunLoop] performSelector: @selector(_stopModalDeferred)
                                         target: self
                                       argument: nil
                                          order: 0
                                          modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
    NSLog(@"Eau: buttonAction scheduled deferred modal stop");
}

- (void) _stopModalDeferred
{
    NSLog(@"Eau: _stopModalDeferred executing");
    [NSApp stopModalWithCode: result];
    NSLog(@"Eau: _stopModalDeferred completed");
    _isStoppingModal = NO;
    _selfRetainer = nil;
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

- (NSInteger) runModal
{
    NSLog(@"Eau: EauAlertPanel runModal called");
    
    // Beep when alert is displayed (diagnostics)
    NSApplication *app = [NSApplication sharedApplication];
    NSLog(@"Eau: EauAlertPanel about to beep - NSApp class: %@ respondsToSelector: %d",
          NSStringFromClass([app class]), (int)[app respondsToSelector:@selector(beep)]);
    if ([app respondsToSelector:@selector(beep)]) {
        [app performSelector:@selector(beep)];
    } else {
        NSLog(@"Eau: NSApp does not respond to -beep");
    }
    
    @try {
        if (isGreen)
        {
            NSLog(@"Eau: EauAlertPanel calling sizePanelToFit");
            [self sizePanelToFit];
            NSLog(@"Eau: EauAlertPanel sizePanelToFit completed");
        }
    
    // Raise the window to ensure it gets input focus
    [NSApp activateIgnoringOtherApps: YES];
    [self orderFrontRegardless];
    [self makeKeyAndOrderFront: self];
    
    // Make sure the default button has focus for Enter key handling
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
    }
    
    EAULOG(@"Eau: runModal - window is key: %d", [self isKeyWindow]);
    EAULOG(@"Eau: runModal - first responder: %@", [self firstResponder]);
    
    NSLog(@"Eau: About to call runModalForWindow");
    result = [NSApp runModalForWindow: self];
    NSLog(@"Eau: runModalForWindow returned with result: %ld", result);
    [self orderOut: self];
    NSLog(@"Eau: EauAlertPanel runModal completed");
    return result;
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in EauAlertPanel runModal: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
        return NSAlertErrorReturn;
    }
}

- (void) keyDown: (NSEvent *)event
{
    NSString *chars = [event characters];
    EAULOG(@"Eau: keyDown received: '%@'", chars);
    if ([chars length] > 0)
    {
        unichar keyChar = [chars characterAtIndex: 0];
    
    // Handle Enter/Return for default button
    if (keyChar == '\r' && useControl(defButton))
    {
        EAULOG(@"Eau: keyDown Enter pressed, clicking default button");
        [self buttonAction: defButton];
        return;
    }
    
    // Handle Spacebar for default button - CRITICAL
    if (keyChar == ' ' && useControl(defButton))
    {
        NSLog(@"Eau: keyDown Spacebar pressed, clicking default button");
        [self buttonAction: defButton];
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
    }
    
    [super keyDown: event];
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
    NSString *chars = [event characters];
    NSUInteger modifiers = [event modifierFlags] & NSDeviceIndependentModifierFlagsMask;
    NSLog(@"Eau: performKeyEquivalent received: '%@', modifiers: %lu, isActivePanel: %d", chars, (unsigned long)modifiers, [self isActivePanel]);
    
    // During modal operation, intercept ALL keyboard events to prevent app shortcuts
    if ([self isActivePanel])
    {
        // Handle Return/Enter for default button
        if ([chars isEqualToString: @"\r"] && useControl(defButton))
        {
            NSLog(@"Eau: performKeyEquivalent Enter pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }
        
        // Handle Spacebar for default button
        if ([chars isEqualToString: @" "] && modifiers == 0 && useControl(defButton))
        {
            NSLog(@"Eau: performKeyEquivalent Spacebar pressed, clicking default button");
            [self buttonAction: defButton];
            return YES;
        }
        
        // Handle Escape for cancel button
        if ([chars isEqualToString: @"\e"] && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
        {
            NSLog(@"Eau: performKeyEquivalent Escape pressed, clicking cancel button");
            [self buttonAction: altButton];
            return YES;
        }
        
        // CRITICAL: Block ALL other keyboard events while modal is active
        // This prevents ANY app-level shortcuts from interfering with the dialog
        // Return YES to consume the event and prevent it from reaching the application
        NSLog(@"Eau: Blocking event during modal: '%@' with modifiers: %lu", chars, (unsigned long)modifiers);
        return YES;  // Consume ALL events to prevent app shortcuts
    }
    
    return [super performKeyEquivalent: event];
}

- (void) sendEvent: (NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString *chars = [event characters];
        NSLog(@"Eau: sendEvent received keyDown: '%@', isActivePanel: %d", chars, [self isActivePanel]);
        
        // CRITICAL: During modal operation, try performKeyEquivalent FIRST
        // This ensures keyboard events are handled by the dialog, not the app
        if ([self isActivePanel])
        {
            if ([self performKeyEquivalent: event])
            {
                NSLog(@"Eau: Event consumed by performKeyEquivalent, not propagating to app");
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
                NSLog(@"Eau: sendEvent Enter pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Spacebar for default button
            if (keyChar == ' ' && useControl(defButton))
            {
                NSLog(@"Eau: sendEvent Spacebar pressed, clicking default button");
                [self buttonAction: defButton];
                return;  // Don't call super - we handled it
            }
            
            // Handle Escape for cancel button
            if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
            {
                NSLog(@"Eau: sendEvent Escape pressed, clicking cancel button");
                [self buttonAction: altButton];
                return;  // Don't call super - we handled it
            }
        }
    }
    [super sendEvent: event];
}

- (BOOL) canBecomeKeyWindow
{
    return YES;
}

- (BOOL) canBecomeMainWindow
{
    return YES;
}

- (void) setTitleBar: (NSString *)titleBar
                icon: (NSImage *)icon
               title: (NSString *)title
             message: (NSString *)message
{
    NSLog(@"Eau: setTitleBar called with title='%@', message='%@'", title, message);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil");
        return;
    }
    
    NSLog(@"Eau: Setting window title");
    if (titleBar != nil)
        [self setTitle: titleBar];
    
    NSLog(@"Eau: Setting icon");
    if (icon != nil)
        [icoButton setImage: icon];
    
    if (title == nil)
        title = titleBar;
    
    NSLog(@"Eau: Setting title field");
    setControl(content, titleField, title);
    
    NSLog(@"Eau: Handling scroll view");
    if (useControl(scroll))
    {
        [scroll setDocumentView: nil];
        [scroll removeFromSuperview];
        [messageField removeFromSuperview];
    }
    
    NSLog(@"Eau: Setting message field");
    setControl(content, messageField, message);
    
    // Always use left alignment for consistent appearance
    [messageField setAlignment: NSLeftTextAlignment];
    
    NSLog(@"Eau: setTitleBar completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
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
    NSLog(@"Eau: setButtons called with %lu buttons", (unsigned long)[buttons count]);
    @try {
    NSView *content = [self contentView];
    if (content == nil)
    {
        NSLog(@"Eau: WARNING - contentView is nil in setButtons");
        return;
    }
    NSUInteger count = [buttons count];
    
    NSLog(@"Eau: Setting button 0");
    setButton(content, defButton, count > 0 ? [buttons objectAtIndex: 0] : nil);
    NSLog(@"Eau: Setting button 1");
    setButton(content, altButton, count > 1 ? [buttons objectAtIndex: 1] : nil);
    NSLog(@"Eau: Setting button 2");
    setButton(content, othButton, count > 2 ? [buttons objectAtIndex: 2] : nil);
    
    NSLog(@"Eau: Setting up first responder");
    if (useControl(defButton))
    {
        [self makeFirstResponder: defButton];
        // Set the default button cell to enable blue pulsing animation
        [self setDefaultButtonCell: [defButton cell]];
    }
    else
        [self makeFirstResponder: self];
    
    NSLog(@"Eau: Setting up key view chain");
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
    
    NSLog(@"Eau: Calling sizePanelToFit from setButtons");
    [self sizePanelToFit];
    NSLog(@"Eau: sizePanelToFit completed from setButtons");
    isGreen = YES;
    result = NSAlertErrorReturn;
    NSLog(@"Eau: setButtons completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
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

/* NSAlert (Eau) Category
 * 
 * Comprehensive NSAlert customization for the Eau theme.
 * 
 * WHAT THIS DOES:
 * - Swizzles NSAlert's _setupPanel to use EauAlertPanel for custom appearance
 * - Swizzles NSAlert's runModal to add focus management for text fields
 * - Ensures any text fields in alerts receive focus immediately when shown
 * - Sets up proper tab navigation between controls in the alert
 * - Configures default button for pulsating animation
 * 
 * WHY WE DO THIS:
 * - Users expect text fields in alerts to be immediately ready for input
 * - The cursor should blink in text fields without requiring a click
 * - Tab key should work to navigate between buttons and controls
 * - Default button should pulse to indicate it's the primary action
 * 
 * FOCUS MANAGEMENT STRATEGY:
 * When an alert appears, we search for editable text fields and set the first
 * one found as the initialFirstResponder. This ensures:
 * 1. The field editor activates automatically
 * 2. The cursor blinks immediately
 * 3. Keyboard input works without clicking
 * 4. Tab navigation is properly configured
 * 
 * If no text field exists, focus goes to the default button.
 */
@implementation NSAlert (Eau)

+ (void) load
{
    static BOOL didSwizzle = NO;
    if (didSwizzle)
        return;
    didSwizzle = YES;
    
    EAULOG(@"Eau: Installing NSAlert customizations");
    // NSLog(@"Eau: Installing NSAlert customizations - FORCED LOG");
    
    // Swizzle NSAlert's _setupPanel to use EauAlertPanel
    Class alertClass = NSClassFromString(@"NSAlert");
    SEL origSetupSel = @selector(_setupPanel);
    SEL swizzledSetupSel = @selector(eau_setupPanel);
    
    // NSLog(@"Eau: Found NSAlert class: %@", alertClass);
    
    Method origSetupMethod = class_getInstanceMethod(alertClass, origSetupSel);
    Method swizzledSetupMethod = class_getInstanceMethod(alertClass, swizzledSetupSel);
    
    // NSLog(@"Eau: Original _setupPanel method: %p", origSetupMethod);
    // NSLog(@"Eau: Swizzled eau_setupPanel method: %p", swizzledSetupMethod);
    
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
        EAULOG(@"Eau: NSAlert _setupPanel swizzled successfully");
        // NSLog(@"Eau: NSAlert _setupPanel swizzled successfully - FORCED LOG");
    }
    else
    {
        EAULOG(@"Eau: Warning - could not find _setupPanel method to swizzle");
        // NSLog(@"Eau: Warning - could not find _setupPanel method to swizzle - FORCED LOG");
    }
    
    // Swizzle NSAlert's runModal to ensure proper activation
    SEL origRunModalSel = @selector(runModal);
    SEL swizzledRunModalSel = @selector(eau_runModal);
    
    Method origRunModalMethod = class_getInstanceMethod(alertClass, origRunModalSel);
    Method swizzledRunModalMethod = class_getInstanceMethod(alertClass, swizzledRunModalSel);
    
    if (origRunModalMethod && swizzledRunModalMethod)
    {
        BOOL didAddRunModal = class_addMethod(alertClass,
                                              origRunModalSel,
                                              method_getImplementation(swizzledRunModalMethod),
                                              method_getTypeEncoding(swizzledRunModalMethod));
        if (didAddRunModal)
        {
            class_replaceMethod(alertClass,
                                swizzledRunModalSel,
                                method_getImplementation(origRunModalMethod),
                                method_getTypeEncoding(origRunModalMethod));
        }
        else
        {
            method_exchangeImplementations(origRunModalMethod, swizzledRunModalMethod);
        }
        EAULOG(@"Eau: NSAlert runModal swizzled successfully");
    }
    else
    {
        EAULOG(@"Eau: Warning - could not find runModal method to swizzle");
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
                EAULOG(@"Eau: GSAlertPanel _initWithoutGModel swizzled successfully");
            }
        }

        // Note: GSAlertPanel runModal/sizePanelToFit swizzles are intentionally
        // disabled here to avoid crashes in legacy alert panels.
    }
}

// Replacement for NSAlert's runModal method
// - Ensures activation and key focus
// - Preserves GNUstep lifecycle (setup, run modal, order out, destroy window)
// - Avoids KVC retain/release side effects on _window
- (NSInteger) eau_runModal
{
    NSLog(@"Eau: NSAlert eau_runModal called");
    @try {

    if (![NSThread isMainThread])
    {
        __block NSInteger result;
        dispatch_sync(dispatch_get_main_queue(), ^{
            result = [self eau_runModal];
        });
        return result;
    }
    
    // Call _setupPanel - this invokes the Eau custom setup since methods were swizzled
    // After swizzling: _setupPanel -> eau_setupPanel code, eau_setupPanel -> original code
    [self performSelector: @selector(_setupPanel)];
    
    // Beep when alert is displayed (diagnostics)
    NSApplication *eauApp = [NSApplication sharedApplication];
    NSLog(@"Eau: NSAlert about to beep - NSApp class: %@ respondsToSelector: %d",
          NSStringFromClass([eauApp class]), (int)[eauApp respondsToSelector:@selector(beep)]);
    if ([eauApp respondsToSelector:@selector(beep)]) {
        [eauApp performSelector:@selector(beep)];
    } else {
        NSLog(@"Eau: NSApp does not respond to -beep");
    }
    
    // Get the _window ivar (NSAlert owns the panel instance)
    NSWindow *window = nil;
    @try {
        window = [self valueForKey: @"_window"];
    }
    @catch (NSException *exception) {
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            window = object_getIvar(self, windowIvar);
        }
    }
    
    if (window)
    {
        NSInteger result = NSAlertErrorReturn;

        // FOCUS MANAGEMENT: Ensure any text fields in the alert receive focus immediately
        // so the cursor blinks and keyboard input works without clicking.
        NSView *contentView = [window contentView];
        if (contentView)
        {
            NSArray *subviews = [contentView subviews];
            NSTextField *firstTextField = nil;
            
            // Search for the first editable text field in the alert
            for (NSView *view in subviews)
            {
                if ([view isKindOfClass:[NSTextField class]])
                {
                    NSTextField *textField = (NSTextField *)view;
                    if ([textField isEditable])
                    {
                        firstTextField = textField;
                        EAULOG(@"NSAlert+Eau: Found editable text field %p in alert", textField);
                        break;
                    }
                }
            }
            
            // Set initial first responder to enable immediate keyboard input
            if (firstTextField)
            {
                EAULOG(@"NSAlert+Eau: Setting initial first responder to text field %p", firstTextField);
                [window setInitialFirstResponder: firstTextField];
            }
            else
            {
                EAULOG(@"NSAlert+Eau: No editable text field found in alert");
            }
        }
        
        // CRITICAL: Make the alert window key so it receives keyboard input immediately.
        // Without this, the alert appears but doesn't have focus - user must click it.
        EAULOG(@"NSAlert+Eau: Activating app and making alert window key for immediate input");
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        EAULOG(@"NSAlert+Eau: Alert window is now key: %d", [window isKeyWindow]);

        if ([window isKindOfClass: [EauAlertPanel class]])
        {
            EauAlertPanel *panel = (EauAlertPanel *)window;
            result = [panel runModal];
        }
        else
        {
            [NSApp activateIgnoringOtherApps: YES];
            [window orderFrontRegardless];
            [window makeKeyAndOrderFront: nil];
            
            EAULOG(@"Eau: NSAlert running modal for window: %@", window);
            [NSApp runModalForWindow: window];
            if ([window respondsToSelector: @selector(result)])
            {
                result = [(EauAlertPanel *)window result];
            }
        }

        [window orderOut: self];

        // Store result via KVC if possible
        @try {
            [self setValue: @(result) forKey: @"_result"];
        }
        @catch (NSException *exception) {
            // Ignore if ivar doesn't exist
        }

        // Defer cleanup to next run loop to avoid use-after-free during modal teardown.
        [[NSRunLoop currentRunLoop] performSelector: @selector(eau_cleanupPanel)
                                             target: self
                                           argument: nil
                                              order: 0
                                              modes: [NSArray arrayWithObjects: NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil]];
        return result;
    }
    
    // Fallback: if window creation failed, return failure
    NSLog(@"Eau: NSAlert eau_runModal - window was nil, returning NSAlertFirstButtonReturn");
    return NSAlertFirstButtonReturn;
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: FATAL EXCEPTION in eau_runModal: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
        return NSAlertErrorReturn;
    }
}

// Cleanup helper to clear NSAlert's window after modal teardown.
- (void)eau_cleanupPanel
{
    Ivar windowIvar = class_getInstanceVariable([self class], "_window");
    if (windowIvar)
    {
        object_setIvar(self, windowIvar, nil);
        objc_setAssociatedObject(self, kEAUAlertWindowRetainKey, nil, OBJC_ASSOCIATION_ASSIGN);
    }
    else
    {
        @try {
            [self setValue: nil forKey: @"_window"];
        }
        @catch (NSException *exception) {
            // Ignore if ivar doesn't exist
        }
    }
}

// Replacement for NSAlert's _setupPanel method
// Builds a themed EauAlertPanel and assigns it to NSAlert's _window ivar.
- (void) eau_setupPanel
{
    NSLog(@"Eau: eau_setupPanel called for NSAlert");
    
    EauAlertPanel *panel;
    NSString *title;
    
    @try {
    NSLog(@"Eau: Creating EauAlertPanel");
    panel = [[EauAlertPanel alloc] init];
    if (panel == nil)
    {
        NSLog(@"Eau: CRITICAL - EauAlertPanel init returned nil");
        return;
    }
    NSLog(@"Eau: EauAlertPanel created successfully: %@", panel);
    
    // Access NSAlert's ivars through KVC or accessor methods
    NSLog(@"Eau: Accessing NSAlert properties");
    NSAlertStyle style = NSWarningAlertStyle;
    NSString *messageText = nil;
    NSString *informativeText = nil;
    NSImage *icon = nil;
    NSArray *buttons = nil;
    
    @try {
        style = [self alertStyle];
        NSLog(@"Eau: alertStyle: %ld", (long)style);
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception getting alertStyle: %@", e);
    }
    
    @try {
        messageText = [self messageText];
        NSLog(@"Eau: messageText: %@", messageText);
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception getting messageText: %@", e);
    }
    
    @try {
        informativeText = [self informativeText];
        NSLog(@"Eau: informativeText: %@", informativeText);
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception getting informativeText: %@", e);
    }
    
    @try {
        icon = [self icon];
        NSLog(@"Eau: icon: %@", icon);
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception getting icon: %@", e);
    }
    
    @try {
        buttons = [self buttons];
        NSLog(@"Eau: buttons count: %lu", (unsigned long)[buttons count]);
    } @catch (NSException *e) {
        NSLog(@"Eau: Exception getting buttons: %@", e);
    }
    
    // Set default icons based on alert style if no custom icon is provided
    if (icon == nil)
    {
        NSLog(@"Eau: No icon provided, using default for style %ld", (long)style);
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
            if (icon != nil)
                NSLog(@"Eau: Loaded default icon: %@", icon);
        } @catch (NSException *e) {
            NSLog(@"Eau: Exception loading default icon: %@", e);
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
    
    NSLog(@"Eau: Setting up panel with title and buttons");
    @try {
        [panel setTitleBar: title
                      icon: icon
                     title: messageText != nil ? messageText : @"Alert"
                   message: informativeText != nil ? informativeText : @""];
        NSLog(@"Eau: setTitleBar completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setTitleBar: %@", e);
    }
    
    @try {
        if ([buttons count] == 0)
        {
            NSLog(@"Eau: No buttons, adding default OK button");
            [self addButtonWithTitle: @"OK"];
            buttons = [self buttons];
        }
        
        NSLog(@"Eau: Setting %lu buttons on panel", (unsigned long)[buttons count]);
        [panel setButtons: buttons];
        NSLog(@"Eau: setButtons completed");
    } @catch (NSException *e) {
        NSLog(@"Eau: EXCEPTION in setButtons: %@", e);
    }
    
    // Set the _window ivar directly when possible to avoid KVC retain/release side effects
    NSLog(@"Eau: Setting _window ivar on NSAlert");
    {
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            object_setIvar(self, windowIvar, panel);
            objc_setAssociatedObject(self, kEAUAlertWindowRetainKey, panel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSLog(@"Eau: Successfully set _window via ivar");
        }
        else
        {
            @try {
                [self setValue: panel forKey: @"_window"];
                NSLog(@"Eau: Successfully set _window via KVC");
            }
            @catch (NSException *exception) {
                NSLog(@"Eau: CRITICAL - could not set _window ivar on NSAlert: %@", exception);
            }
        }
    }
    
    NSLog(@"Eau: eau_setupPanel completed successfully");
    }
    @catch (NSException *exception) {
        NSLog(@"Eau: FATAL EXCEPTION in eau_setupPanel: %@", exception);
        NSLog(@"Eau: Exception reason: %@", [exception reason]);
        NSLog(@"Eau: Exception stack: %@", [exception callStackSymbols]);
    }
}

@end
