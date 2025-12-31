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

// Constants for panel layout - modern centered appearance
static const float WinMinWidth = 420.0;
static const float WinMinHeight = 130.0;
static const float IconSide = 64.0;
static const float IconLeft = 20.0;
static const float IconTop = 20.0;
static const float TextLeft = 100.0;       // Left edge for both title and message
static const float TextRight = 20.0;       // Right margin
static const float TitleTop = 20.0;        // Distance from top to title
static const float TitleMessageGap = 14.0;  // Gap between title and message
static const float ButtonBottom = 14.0;
static const float ButtonMargin = 20.0;
static const float ButtonInterspace = 12.0;
static const float ButtonMinHeight = 24.0;
static const float ButtonMinWidth = 72.0;
static const float ContentBottomMargin = 20.0;

#define SIZE_SCALE 0.6
#define TitleFont [NSFont boldSystemFontOfSize: 0]
#define MessageFont [NSFont systemFontOfSize: 0]

#define useControl(control) ([control superview] != nil)

// Forward declarations
static void setControl(NSView *content, id control, NSString *title);
static void setButton(NSView *content, NSButton *control, NSButton *templateBtn);
static void setKeyEquivalent(NSButton *button);
static NSScrollView *makeScrollViewWithRect(NSRect rect);

#pragma mark - EauAlertPanel Implementation

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
    self = [super initWithContentRect: rect
                            styleMask: NSTitledWindowMask
                              backing: NSBackingStoreRetained
                                defer: YES];
    if (self == nil)
        return nil;
    
    [self setTitle: @" "];
    [self setLevel: NSModalPanelWindowLevel];
    [self setHidesOnDeactivate: NO];
    [self setBecomesKeyOnlyIfNeeded: NO];
    
    NSView *content = [self contentView];
    NSFont *titleFont = TitleFont;
    
    // Icon button - positioned at top left
    NSRect iconRect = NSMakeRect(IconLeft, 
                                  rect.size.height - IconTop - IconSide,
                                  IconSide, IconSide);
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
    NSRect titleRect = NSMakeRect(TextLeft, 0, 0, 0);
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
    [messageField setFont: MessageFont];
    [[messageField cell] setWraps: YES];
    [[messageField cell] setLineBreakMode: NSLineBreakByWordWrapping];
    
    // Buttons
    defButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertDefaultReturn];
    [defButton setKeyEquivalent: @"\r"];
    NSLog(@"Eau: defButton key equivalent set to: '%@' - FORCED LOG", [defButton keyEquivalent]);
    [defButton setHighlightsBy: NSPushInCellMask | NSChangeGrayCellMask | NSContentsCellMask];
    [defButton setImagePosition: NSImageRight];
    [defButton setImage: [NSImage imageNamed: @"common_ret"]];
    [defButton setAlternateImage: [NSImage imageNamed: @"common_retH"]];
    [defButton setFont: titleFont];  // Mark as default with bold font
    
    altButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertAlternateReturn];
    othButton = [self _makeButtonWithRect: NSZeroRect tag: NSAlertOtherReturn];
    
    // Scroll view for long messages
    scroll = makeScrollViewWithRect(NSMakeRect(0, 0, 80, 80));
    
    result = NSAlertErrorReturn;
    isGreen = YES;
    
    return self;
}

- (id) init
{
    NSLog(@"Eau: EauAlertPanel init called - FORCED LOG");
    return [self initWithContentRect: NSMakeRect(0, 0, WinMinWidth, WinMinHeight)];
}

// Helper method that will be injected into GSAlertPanel via swizzling
// This calls the original _initWithoutGModel and then removes the horizontal line
- (id) eau_initWithoutGModelHelper
{
    // Call the original implementation (which is now at this selector after swizzling)
    self = [self eau_initWithoutGModel];
    if (self == nil)
        return nil;
    
    // Remove the horizontal line (NSBox with NSGrooveBorder)
    NSView *content = [(NSPanel *)self contentView];
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
    [subviews release];
    
    return self;
}

- (void) dealloc
{
    RELEASE(defButton);
    RELEASE(altButton);
    RELEASE(othButton);
    RELEASE(icoButton);
    RELEASE(titleField);
    RELEASE(messageField);
    RELEASE(scroll);
    [super dealloc];
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
    ssize.width = SIZE_SCALE * ssize.width;
    ssize.height = SIZE_SCALE * ssize.height;
    
    // Start with minimum width
    wsize.width = WinMinWidth;
    textAreaWidth = wsize.width - TextLeft - TextRight;
    
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
    bsize.width = ButtonMinWidth;
    bsize.height = ButtonMinHeight;
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
    float textContentHeight = TitleTop + titleHeight;
    if (messageHeight > 0)
    {
        textContentHeight += TitleMessageGap + messageHeight;
    }
    textContentHeight += ContentBottomMargin;
    
    if (numberOfButtons > 0)
    {
        textContentHeight += bsize.height + ButtonBottom;
    }
    
    // Ensure icon has enough space (icon height + margins)
    float iconContentHeight = IconTop + IconSide + ContentBottomMargin;
    if (numberOfButtons > 0)
    {
        iconContentHeight += bsize.height + ButtonBottom;
    }
    
    wsize.height = (textContentHeight > iconContentHeight) ? textContentHeight : iconContentHeight;
    
    // Resize window if message is too long
    if (ssize.height < wsize.height)
    {
        wsize.height = ssize.height;
        needsScroll = couldNeedScroll;
    }
    else if (wsize.height < WinMinHeight)
    {
        wsize.height = WinMinHeight;
    }
    
    if (needsScroll)
        wsize.width += [NSScroller scrollerWidth] + 4.0;
    
    if (ssize.width < wsize.width)
        wsize.width = ssize.width;
    else if (wsize.width < WinMinWidth)
        wsize.width = WinMinWidth;
    
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
        NSRect iconRect = NSMakeRect(IconLeft,
                                      bounds.size.height - IconTop - IconSide,
                                      IconSide, IconSide);
        [icoButton setFrame: iconRect];
    }
    
    // Place buttons at bottom right
    if (numberOfButtons > 0)
    {
        position = bounds.origin.x + bounds.size.width - ButtonMargin;
        for (i = 0; i < 3; i++)
        {
            if (useControl(buttons[i]))
            {
                NSRect rect;
                position -= bsize.width;
                rect.origin.x = position;
                rect.origin.y = bounds.origin.y + ButtonBottom;
                rect.size.width = bsize.width;
                rect.size.height = bsize.height;
                [buttons[i] setFrame: rect];
                position -= ButtonInterspace;
            }
        }
    }
    
    // Calculate vertical positions for title and message
    float buttonAreaHeight = (numberOfButtons > 0) ? (ButtonBottom + bsize.height) : 0;
    
    // Place title at top, left-aligned with TextLeft
    float currentY = bounds.size.height - TitleTop;
    if (useControl(titleField))
    {
        NSRect trect = [titleField frame];
        trect.origin.x = TextLeft;
        trect.size.width = bounds.size.width - TextLeft - TextRight;
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
            
            srect.origin.x = TextLeft;
            srect.origin.y = buttonAreaHeight + ContentBottomMargin;
            srect.size.width = bounds.size.width - TextLeft - TextRight;
            srect.size.height = currentY - TitleMessageGap - srect.origin.y;
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
            currentY -= TitleMessageGap;
            mrect.origin.x = TextLeft;
            mrect.size.width = bounds.size.width - TextLeft - TextRight;
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
    [content display];
}

- (void) buttonAction: (id)sender
{
    EAULOG(@"Eau: buttonAction called, sender: %@, tag: %ld", sender, [sender tag]);
    if (![self isActivePanel])
    {
        NSLog(@"EauAlertPanel buttonAction: when not in modal loop");
        return;
    }
    result = [sender tag];
    EAULOG(@"Eau: buttonAction stopping modal with result: %ld", result);
    [NSApp stopModalWithCode: result];
}

- (NSInteger) result
{
    return result;
}

- (BOOL) isActivePanel
{
    return [NSApp modalWindow] == self;
}

- (NSInteger) runModal
{
    NSLog(@"Eau: runModal called - FORCED LOG");
    if (isGreen)
        [self sizePanelToFit];
    
    // Ensure we're the key window and can handle events
    [self center];
    [self makeKeyAndOrderFront: self];
    EAULOG(@"Eau: runModal - window is key: %d", [self isKeyWindow]);
    EAULOG(@"Eau: runModal - first responder: %@", [self firstResponder]);
    NSLog(@"Eau: About to call runModalForWindow - FORCED LOG");
    
    result = [NSApp runModalForWindow: self];
    NSLog(@"Eau: runModalForWindow returned with result: %ld - FORCED LOG", result);
    [self orderOut: self];
    return result;
}

- (void) keyDown: (NSEvent *)event
{
    NSString *chars = [event characters];
    EAULOG(@"Eau: keyDown received: '%@'", chars);
    unichar keyChar = [chars characterAtIndex: 0];
    
    // Handle Enter/Return for default button
    if (keyChar == '\r' && useControl(defButton))
    {
        EAULOG(@"Eau: keyDown Enter pressed, clicking default button");
        [defButton performClick: self];
        return;
    }
    
    // Handle Escape for Cancel button
    if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
    {
        [altButton performClick: self];
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
    
    [super keyDown: event];
}

- (BOOL) performKeyEquivalent: (NSEvent *)event
{
    NSString *chars = [event characters];
    EAULOG(@"Eau: performKeyEquivalent received: '%@'", chars);
    if ([chars isEqualToString: @"\r"] && useControl(defButton))
    {
        EAULOG(@"Eau: performKeyEquivalent Enter pressed, clicking default button");
        [defButton performClick: self];
        return YES;
    }
    if ([chars isEqualToString: @"\e"] && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
    {
        EAULOG(@"Eau: performKeyEquivalent Escape pressed, clicking cancel button");
        [altButton performClick: self];
        return YES;
    }
    return [super performKeyEquivalent: event];
}

- (void) sendEvent: (NSEvent *)event
{
    if ([event type] == NSKeyDown)
    {
        NSString *chars = [event characters];
        EAULOG(@"Eau: sendEvent received keyDown: '%@'", chars);
        if ([chars length] > 0)
        {
            unichar keyChar = [chars characterAtIndex: 0];
            EAULOG(@"Eau: keyChar = %d (0x%X)", keyChar, keyChar);
            if (keyChar == '\r' && useControl(defButton))
            {
                EAULOG(@"Eau: Enter pressed, clicking default button");
                [defButton performClick: self];
                return;
            }
            if (keyChar == 0x1B && useControl(altButton) && [[altButton title] isEqualToString: @"Cancel"])
            {
                EAULOG(@"Eau: Escape pressed, clicking cancel button");
                [altButton performClick: self];
                return;
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
    NSView *content = [self contentView];
    
    if (titleBar != nil)
        [self setTitle: titleBar];
    
    if (icon != nil)
        [icoButton setImage: icon];
    
    if (title == nil)
        title = titleBar;
    
    setControl(content, titleField, title);
    
    if (useControl(scroll))
    {
        [scroll setDocumentView: nil];
        [scroll removeFromSuperview];
        [messageField removeFromSuperview];
    }
    
    setControl(content, messageField, message);
    
    // Always use left alignment for consistent appearance
    [messageField setAlignment: NSLeftTextAlignment];
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
        [self makeFirstResponder: defButton];
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
    NSLog(@"Eau: setButtons called with %lu buttons - FORCED LOG", [buttons count]);
    NSView *content = [self contentView];
    NSUInteger count = [buttons count];
    
    setButton(content, defButton, count > 0 ? [buttons objectAtIndex: 0] : nil);
    setButton(content, altButton, count > 1 ? [buttons objectAtIndex: 1] : nil);
    setButton(content, othButton, count > 2 ? [buttons objectAtIndex: 2] : nil);
    
    if (useControl(defButton))
        [self makeFirstResponder: defButton];
    else
        [self makeFirstResponder: self];
    
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
    
    [self sizePanelToFit];
    isGreen = YES;
    result = NSAlertErrorReturn;
}

@end

#pragma mark - Helper Functions

static NSScrollView *makeScrollViewWithRect(NSRect rect)
{
    float lineHeight = [MessageFont boundingRectForFont].size.height;
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
        NSLog(@"Eau: setButton - template title: '%@', keyEquiv: '%@' - FORCED LOG", [templateBtn title], [templateBtn keyEquivalent]);
        [control setTitle: [templateBtn title]];
        [control setKeyEquivalent: [templateBtn keyEquivalent]];
        [control setKeyEquivalentModifierMask: [templateBtn keyEquivalentModifierMask]];
        [control setTag: [templateBtn tag]];
        [control sizeToFit];
        NSLog(@"Eau: setButton - control after setup: title='%@', keyEquiv='%@', tag=%ld - FORCED LOG", [control title], [control keyEquivalent], [control tag]);
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
    
    // Also swizzle GSAlertPanel's _initWithoutGModel to handle legacy alert functions
    // (NSRunAlertPanel, NSGetAlertPanel, etc.) which create GSAlertPanel directly
    Class gsAlertPanelClass = NSClassFromString(@"GSAlertPanel");
    if (gsAlertPanelClass)
    {
        SEL origInitSel = @selector(_initWithoutGModel);
        SEL swizzledInitSel = @selector(eau_initWithoutGModel);
        
        // Add the swizzled method to GSAlertPanel dynamically
        Method rikInitMethod = class_getInstanceMethod([EauAlertPanel class], @selector(eau_initWithoutGModelHelper));
        if (rikInitMethod)
        {
            class_addMethod(gsAlertPanelClass,
                           swizzledInitSel,
                           method_getImplementation(rikInitMethod),
                           method_getTypeEncoding(rikInitMethod));
            
            Method origInitMethod = class_getInstanceMethod(gsAlertPanelClass, origInitSel);
            Method newSwizzledMethod = class_getInstanceMethod(gsAlertPanelClass, swizzledInitSel);
            
            if (origInitMethod && newSwizzledMethod)
            {
                method_exchangeImplementations(origInitMethod, newSwizzledMethod);
                EAULOG(@"Eau: GSAlertPanel _initWithoutGModel swizzled successfully");
            }
        }
    }
}

// Replacement for NSAlert's _setupPanel method
- (void) eau_setupPanel
{
    NSLog(@"Eau: eau_setupPanel called - FORCED LOG");
    EAULOG(@"Eau: eau_setupPanel called");
    
    EauAlertPanel *panel;
    NSString *title;
    
    NSLog(@"Eau: Creating EauAlertPanel - FORCED LOG");
    panel = [[EauAlertPanel alloc] init];
    NSLog(@"Eau: EauAlertPanel created: %@ - FORCED LOG", panel);
    
    // Access NSAlert's ivars through KVC or accessor methods
    NSAlertStyle style = [self alertStyle];
    NSString *messageText = [self messageText];
    NSString *informativeText = [self informativeText];
    NSImage *icon = [self icon];
    NSArray *buttons = [self buttons];
    
    // Set default icons based on alert style if no custom icon is provided
    if (icon == nil)
    {
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
    
    [panel setTitleBar: title
                  icon: icon
                 title: messageText != nil ? messageText : @"Alert"
               message: informativeText != nil ? informativeText : @""];
    
    if ([buttons count] == 0)
    {
        [self addButtonWithTitle: @"OK"];
        buttons = [self buttons];
    }
    
    [panel setButtons: buttons];
    
    // Set the _window ivar using KVC
    // NSAlert stores its window in an ivar called _window
    @try {
        [self setValue: panel forKey: @"_window"];
    }
    @catch (NSException *exception) {
        // If KVC fails, try using the object_setInstanceVariable approach
        Ivar windowIvar = class_getInstanceVariable([self class], "_window");
        if (windowIvar)
        {
            object_setIvar(self, windowIvar, panel);
        }
        else
        {
            EAULOG(@"Eau: Warning - could not set _window ivar on NSAlert");
        }
    }
}

@end
