/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauTestWindowController.h"
#import "EauTestFormBuilder.h"
#import "EauTestListDataSource.h"
#import "AppearanceMetrics.h"

static const CGFloat EauTestWindowWidth = 580.0;
static const CGFloat EauTestWindowHeight = 440.0;
static const CGFloat EauTestFieldWidth = 280.0;

static NSButton *makePushButton(NSString *title, id target, SEL action)
{
  NSButton *button = [[NSButton alloc] initWithFrame:
    NSMakeRect(0, 0, METRICS_BUTTON_MIN_WIDTH, METRICS_BUTTON_HEIGHT)];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setButtonType: NSMomentaryPushInButton];
  [button setTitle: title];
  [button setTarget: target];
  [button setAction: action];
  return button;
}

static NSButton *makeSwitch(NSString *title, NSInteger state, BOOL enabled)
{
  NSButton *button = [[NSButton alloc] initWithFrame:
    NSMakeRect(0, 0, 90, METRICS_RADIO_BUTTON_SIZE)];
  [button setButtonType: NSSwitchButton];
  [button setTitle: title];
  [button setState: state];
  [button setEnabled: enabled];
  return button;
}

static NSButton *makeBezelButton(NSBezelStyle style, CGFloat side)
{
  NSButton *button = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, side, side)];
  [button setBezelStyle: style];
  [button setButtonType: NSPushOnPushOffButton];
  [button setTitle: @""];
  return button;
}

static NSRect fieldFrame(CGFloat width)
{
  return NSMakeRect(0, 0, width, METRICS_TEXT_INPUT_FIELD_HEIGHT);
}

/* Eau creates every text field cell unbezeled so labels look right; input
 * fields have to ask for their bezel explicitly. */
static id makeInputField(Class fieldClass, CGFloat width)
{
  NSTextField *field = [[fieldClass alloc] initWithFrame: fieldFrame(width)];
  [field setBezeled: YES];
  [field setEditable: YES];
  [field setDrawsBackground: YES];
  return field;
}

@implementation EauTestWindowController
{
  NSWindow *_window;
  NSTextField *_textField;
  EauTestListDataSource *_listData;
  NSProgressIndicator *_indeterminateBar;
  NSProgressIndicator *_spinner;
  /* A sheet does not own its alert; without this the alert would be
   * deallocated under ARC while the sheet is still up. */
  NSAlert *_sheetAlert;
}

- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _listData = [[EauTestListDataSource alloc] init];
      [self buildWindow];
    }
  return self;
}

- (void)showWindow
{
  [_window makeKeyAndOrderFront: nil];
  [_window makeFirstResponder: _textField];
  /* Animation is started only once the window is on screen; GNUstep stops
   * indeterminate indicators that are not in a visible window. */
  [_indeterminateBar startAnimation: nil];
  [_spinner startAnimation: nil];
}

- (void)buildWindow
{
  _window = [[NSWindow alloc]
    initWithContentRect: NSMakeRect(0, 0, EauTestWindowWidth, EauTestWindowHeight)
              styleMask: NSTitledWindowMask | NSClosableWindowMask
                         | NSMiniaturizableWindowMask | NSResizableWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  [_window setTitle: @"EauTest"];
  [_window setMinSize: NSMakeSize(METRICS_WIN_MIN_WIDTH, EauTestWindowHeight)];
  [_window setReleasedWhenClosed: NO];
  [_window center];

  NSView *content = [_window contentView];
  NSRect bounds = [content bounds];

  NSButton *ok = makePushButton(@"OK", self, @selector(dismiss:));
  [ok setKeyEquivalent: @"\r"];
  [ok setFrameOrigin: NSMakePoint(
    NSMaxX(bounds) - METRICS_CONTENT_SIDE_MARGIN - METRICS_BUTTON_MIN_WIDTH,
    METRICS_CONTENT_BOTTOM_MARGIN)];
  [ok setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview: ok];
  /* The default button is what makes Eau pulse it. */
  [_window setDefaultButtonCell: [ok cell]];

  NSButton *cancel = makePushButton(@"Cancel", self, @selector(dismiss:));
  [cancel setKeyEquivalent: @"\e"];
  [cancel setFrameOrigin: NSMakePoint(
    NSMinX([ok frame]) - METRICS_BUTTON_HORIZ_INTERSPACE - METRICS_BUTTON_MIN_WIDTH,
    METRICS_CONTENT_BOTTOM_MARGIN)];
  [cancel setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
  [content addSubview: cancel];

  CGFloat tabBottom = NSMaxY([ok frame]) + METRICS_BUTTON_VERT_INTERSPACE;
  NSTabView *tabs = [[NSTabView alloc] initWithFrame: NSMakeRect(
    METRICS_CONTENT_SIDE_MARGIN, tabBottom,
    NSWidth(bounds) - 2 * METRICS_CONTENT_SIDE_MARGIN,
    NSHeight(bounds) - METRICS_CONTENT_TOP_MARGIN - tabBottom)];
  [tabs setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [content addSubview: tabs];

  [self addPaneWithLabel: @"Text" toTabView: tabs builder: @selector(buildTextPane:)];
  [self addPaneWithLabel: @"Buttons" toTabView: tabs builder: @selector(buildButtonsPane:)];
  [self addPaneWithLabel: @"Values" toTabView: tabs builder: @selector(buildValuesPane:)];
  [self addPaneWithLabel: @"Lists" toTabView: tabs builder: @selector(buildListsPane:)];
  [tabs selectTabViewItemAtIndex: 0];

  [_window setInitialFirstResponder: _textField];
}

- (void)addPaneWithLabel:(NSString *)label
               toTabView:(NSTabView *)tabs
                 builder:(SEL)builder
{
  NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier: label];
  [item setLabel: label];
  /* Rows are laid out against the pane's final size; the tab view only
   * resizes an item's view when it is selected, which is too late. */
  NSView *pane = [[NSView alloc] initWithFrame: [tabs contentRect]];
  [pane setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];
  ((void (*)(id, SEL, EauTestFormBuilder *))[self methodForSelector: builder])
    (self, builder, form);
  [item setView: pane];
  [tabs addTabViewItem: item];
}

- (void)buildTextPane:(EauTestFormBuilder *)form
{
  _textField = makeInputField([NSTextField class], EauTestFieldWidth);
  [form addRowWithLabel: @"Text Field:" controls: @[ _textField ]];

  NSSecureTextField *secure = makeInputField([NSSecureTextField class], EauTestFieldWidth);
  [secure setStringValue: @"secret"];
  [form addRowWithLabel: @"Secure Field:" controls: @[ secure ]];

  NSSearchField *search = [[NSSearchField alloc] initWithFrame: fieldFrame(EauTestFieldWidth)];
  [form addRowWithLabel: @"Search Field:" controls: @[ search ]];

  NSComboBox *combo = makeInputField([NSComboBox class], EauTestFieldWidth);
  [combo addItemsWithObjectValues: @[ @"Red", @"Green", @"Blue" ]];
  [combo selectItemAtIndex: 0];
  [combo setStringValue: @"Red"];
  [form addRowWithLabel: @"Combo Box:" controls: @[ combo ]];

  NSTextField *disabled = makeInputField([NSTextField class], EauTestFieldWidth);
  [disabled setStringValue: @"Disabled"];
  [disabled setEnabled: NO];
  [form addRowWithLabel: @"Disabled Field:" controls: @[ disabled ]];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
    NSMakeRect(0, 0, EauTestFieldWidth, 80)];
  [scroll setHasVerticalScroller: YES];
  [scroll setBorderType: NSBezelBorder];
  NSTextView *textView = [[NSTextView alloc] initWithFrame:
    NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)];
  [textView setAutoresizingMask: NSViewWidthSizable];
  [textView setAllowsUndo: YES];
  [textView setString: @"A multi-line text view.\nIt scrolls once the text "
    @"grows beyond its height.\nThird line.\nFourth line.\nFifth line."];
  [scroll setDocumentView: textView];
  [form addRowWithLabel: @"Text View:" controls: @[ scroll ]];
}

- (void)buildButtonsPane:(EauTestFormBuilder *)form
{
  NSButton *disabledPush = makePushButton(@"Disabled", nil, NULL);
  [disabledPush setEnabled: NO];
  [form addRowWithLabel: @"Push Buttons:" controls: @[
    makePushButton(@"Show Alert", self, @selector(showAlert:)),
    makePushButton(@"Show Sheet", self, @selector(showSheet:)),
    disabledPush ]];

  NSButton *small = makePushButton(@"Small", nil, NULL);
  [[small cell] setControlSize: NSSmallControlSize];
  [small setFrameSize: NSMakeSize(METRICS_BUTTON_MIN_WIDTH, METRICS_BUTTON_SMALL_HEIGHT)];
  [form addRowWithLabel: @"Small Button:" controls: @[ small ]];

  [form addRowWithLabel: @"Check Boxes:" controls: @[
    makeSwitch(@"On", NSOnState, YES),
    makeSwitch(@"Off", NSOffState, YES),
    makeSwitch(@"Disabled", NSOnState, NO) ]];

  NSButtonCell *radioPrototype = [[NSButtonCell alloc] init];
  [radioPrototype setButtonType: NSRadioButton];
  NSMatrix *radios = [[NSMatrix alloc]
    initWithFrame: NSMakeRect(0, 0, 3 * 90, METRICS_RADIO_BUTTON_SIZE)
             mode: NSRadioModeMatrix
        prototype: radioPrototype
     numberOfRows: 1
  numberOfColumns: 3];
  [radios setCellSize: NSMakeSize(90, METRICS_RADIO_BUTTON_SIZE)];
  NSArray *radioTitles = @[ @"First", @"Second", @"Third" ];
  for (NSUInteger i = 0; i < [radioTitles count]; i++)
    [[radios cellAtRow: 0 column: (NSInteger)i] setTitle: [radioTitles objectAtIndex: i]];
  [radios selectCellAtRow: 0 column: 0];
  [form addRowWithLabel: @"Radio Buttons:" controls: @[ radios ]];

  NSPopUpButton *popUp = [[NSPopUpButton alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT) pullsDown: NO];
  [popUp addItemsWithTitles: @[ @"Small", @"Medium", @"Large" ]];
  NSPopUpButton *pullDown = [[NSPopUpButton alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT) pullsDown: YES];
  [pullDown addItemsWithTitles: @[ @"Actions", @"Rename", @"Duplicate" ]];
  [form addRowWithLabel: @"Pop-Up Buttons:" controls: @[ popUp, pullDown ]];

  NSSegmentedControl *segments = [[NSSegmentedControl alloc]
    initWithFrame: NSMakeRect(0, 0, 240, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
  [segments setSegmentCount: 3];
  NSArray *segmentTitles = @[ @"Icons", @"List", @"Columns" ];
  for (NSUInteger i = 0; i < [segmentTitles count]; i++)
    {
      [segments setLabel: [segmentTitles objectAtIndex: i] forSegment: (NSInteger)i];
      [segments setWidth: 80 forSegment: (NSInteger)i];
    }
  [segments setSelectedSegment: 0];
  [form addRowWithLabel: @"Segmented:" controls: @[ segments ]];

  [form addRowWithLabel: @"Disclosure, Help:" controls: @[
    makeBezelButton(NSDisclosureBezelStyle, 13),
    makeBezelButton(NSHelpButtonBezelStyle, 21) ]];
}

- (void)buildValuesPane:(EauTestFormBuilder *)form
{
  NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 21)];
  [slider setMinValue: 0];
  [slider setMaxValue: 100];
  [slider setDoubleValue: 40];
  [form addRowWithLabel: @"Slider:" controls: @[ slider ]];

  NSTextField *stepperValue = makeInputField([NSTextField class], 60);
  [stepperValue setIntegerValue: 5];
  NSStepper *stepper = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 15, 22)];
  [stepper setMinValue: 0];
  [stepper setMaxValue: 10];
  [stepper setIntegerValue: 5];
  [stepper setTarget: stepperValue];
  [stepper setAction: @selector(takeIntegerValueFrom:)];
  [form addRowWithLabel: @"Stepper:" controls: @[ stepperValue, stepper ]];

  NSColorWell *well = [[NSColorWell alloc] initWithFrame: NSMakeRect(0, 0, 52, 26)];
  [well setColor: [NSColor colorWithCalibratedRed: 0.2 green: 0.5 blue: 0.9 alpha: 1.0]];
  [form addRowWithLabel: @"Color Well:" controls: @[ well ]];

  NSProgressIndicator *determinate = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 20)];
  [determinate setIndeterminate: NO];
  [determinate setDoubleValue: 60];
  [form addRowWithLabel: @"Progress:" controls: @[ determinate ]];

  _indeterminateBar = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 20)];
  [_indeterminateBar setIndeterminate: YES];
  [form addRowWithLabel: @"Indeterminate:" controls: @[ _indeterminateBar ]];

  _spinner = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 32, 32)];
  [_spinner setStyle: NSProgressIndicatorSpinningStyle];
  [form addRowWithLabel: @"Spinning:" controls: @[ _spinner ]];

  NSBox *box = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 60)];
  [box setTitle: @"Box Title"];
  [form addRowWithLabel: @"Box:" controls: @[ box ]];
}

- (void)buildListsPane:(EauTestFormBuilder *)form
{
  NSScrollView *tableScroll = [[NSScrollView alloc]
    initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 120)];
  [tableScroll setHasVerticalScroller: YES];
  [tableScroll setBorderType: NSBezelBorder];
  NSTableView *table = [[NSTableView alloc] initWithFrame: [[tableScroll contentView] bounds]];
  for (NSString *identifier in @[ @"name", @"kind" ])
    {
      NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: identifier];
      [[column headerCell] setStringValue: [identifier capitalizedString]];
      [column setWidth: (EauTestFieldWidth - METRICS_SCROLLBAR_WIDTH) / 2 - 4];
      [table addTableColumn: column];
    }
  [table setDataSource: (id)_listData];
  [table setUsesAlternatingRowBackgroundColors: YES];
  [tableScroll setDocumentView: table];
  [form addRowWithLabel: @"Table:" controls: @[ tableScroll ]];

  NSBrowser *browser = [[NSBrowser alloc] initWithFrame: NSMakeRect(0, 0, EauTestFieldWidth, 120)];
  [browser setMaxVisibleColumns: 2];
  [browser setDelegate: (id)_listData];
  [browser loadColumnZero];
  [form addRowWithLabel: @"Browser:" controls: @[ browser ]];
}

- (void)dismiss:(id)sender
{
  [_window performClose: sender];
}

- (NSAlert *)sampleAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText: @"Sample Alert"];
  [alert setInformativeText: @"Shows how Eau draws an alert panel."];
  [alert addButtonWithTitle: @"OK"];
  [alert addButtonWithTitle: @"Cancel"];
  return alert;
}

- (void)showAlert:(id)sender
{
  [[self sampleAlert] runModal];
}

- (void)showSheet:(id)sender
{
  _sheetAlert = [self sampleAlert];
  [_sheetAlert beginSheetModalForWindow: _window
                                 modalDelegate: nil
                                didEndSelector: NULL
                                   contextInfo: NULL];
}

@end
