/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "EauShowcaseWindowController.h"
#import "EauShowcaseSectionRegistry.h"
#import "EauMetricsChecker.h"
#import "EauShowcaseMetricsOverlayView.h"
#import "EauTestControlFactory.h"
#import "EauTestFormBuilder.h"
#import "EauTestListDataSource.h"
#import "EauTestWindowController.h"
#import "AppearanceMetrics.h"
#import <objc/runtime.h>

static const CGFloat EauShowcaseWindowWidth = 940.0;
static const CGFloat EauShowcaseWindowHeight = 640.0;
static const CGFloat EauShowcaseSidebarWidth = 200.0;
static const CGFloat EauShowcaseHeaderHeight = 24.0;
static const CGFloat EauShowcaseFieldWidth = 260.0;

/* --- per-control ground truth for the runtime metrics scan ---
 *
 * The scan needs to know, for an arbitrary NSView pulled out of a built
 * pane, "what AppearanceMetrics height rule (if any) applies to this
 * control".  Re-deriving that from bezel style / button type after the
 * fact is guesswork; tagging each control with the rule we already know
 * when we build it is exact.  Associated objects keep this off NSView
 * itself (no subclassing every control just to carry two extra fields). */
static const void *EauShowcaseNameKey = &EauShowcaseNameKey;
static const void *EauShowcaseHeightKey = &EauShowcaseHeightKey;
static const void *EauShowcaseExcludeKey = &EauShowcaseExcludeKey;

static void EauShowcaseTag(NSView *view, NSString *name, CGFloat requiredHeight)
{
  objc_setAssociatedObject(view, EauShowcaseNameKey, name, OBJC_ASSOCIATION_RETAIN);
  if (requiredHeight > 0)
    objc_setAssociatedObject(view, EauShowcaseHeightKey,
      [NSNumber numberWithDouble: requiredHeight], OBJC_ASSOCIATION_RETAIN);
}

/* Marks a view (a documentation mock-up, a decorative overlay) that the
 * "Compare with metrics" scan must never wrap - it is not a control an
 * AppearanceMetrics rule applies to. */
static void EauShowcaseExcludeFromScan(NSView *view)
{
  objc_setAssociatedObject(view, EauShowcaseExcludeKey,
    [NSNumber numberWithBool: YES], OBJC_ASSOCIATION_RETAIN);
}

static BOOL EauShowcaseIsExcludedFromScan(NSView *view)
{
  return [objc_getAssociatedObject(view, EauShowcaseExcludeKey) boolValue];
}

static CGFloat EauShowcaseExpectedHeight(NSView *view)
{
  NSNumber *height = objc_getAssociatedObject(view, EauShowcaseHeightKey);
  return (height != nil) ? [height doubleValue] : 0;
}

static NSString *EauShowcaseControlName(NSView *view)
{
  NSString *name = objc_getAssociatedObject(view, EauShowcaseNameKey);
  return (name != nil) ? name : NSStringFromClass([view class]);
}

static NSButton *ShowcaseButton(NSString *title, id target, SEL action, NSControlSize size)
{
  NSButton *button = [EauTestControlFactory pushButtonWithTitle: title target: target
                                                          action: action controlSize: size];
  EauShowcaseTag(button, [title stringByAppendingString: @" button"],
    (size == NSSmallControlSize) ? METRICS_BUTTON_SMALL_HEIGHT : METRICS_BUTTON_HEIGHT);
  return button;
}

static NSButton *ShowcaseSwitch(NSString *title, NSInteger state, BOOL enabled, NSControlSize size)
{
  NSButton *button = [EauTestControlFactory switchWithTitle: title state: state
                                                      enabled: enabled controlSize: size];
  EauShowcaseTag(button, [title stringByAppendingString: @" checkbox"],
    (size == NSSmallControlSize) ? METRICS_RADIO_BUTTON_SMALL_SIZE : METRICS_RADIO_BUTTON_SIZE);
  return button;
}

static id ShowcaseInputField(Class fieldClass, NSString *name, CGFloat width)
{
  id field = [EauTestControlFactory inputFieldOfClass: fieldClass width: width];
  EauShowcaseTag(field, name, METRICS_TEXT_INPUT_FIELD_HEIGHT);
  return field;
}

static NSTextField *ShowcaseValueField(NSString *value, CGFloat width)
{
  NSTextField *field = ShowcaseInputField([NSTextField class], @"value field", width);
  [field setStringValue: value];
  return field;
}

static NSView *NewPane(NSRect bounds)
{
  NSView *pane = [[NSView alloc] initWithFrame: bounds];
  [pane setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  return pane;
}

/* --- the window's root view: relayouts on every resize, per the
 * gnustep-code-built-ui house pattern (never lay out once and hope). --- */
@interface EauShowcaseMainView : NSView
{
  __weak EauShowcaseWindowController *_owner;
}
- (instancetype)initWithFrame: (NSRect)frame owner: (EauShowcaseWindowController *)owner;
@end

@interface EauShowcaseWindowController ()
- (void)relayoutSubviewsForSize: (NSSize)size;
@end

@implementation EauShowcaseMainView

- (instancetype)initWithFrame: (NSRect)frame owner: (EauShowcaseWindowController *)owner
{
  if ((self = [super initWithFrame: frame]) != nil)
    _owner = owner;
  return self;
}

- (void)setFrameSize: (NSSize)size
{
  [super setFrameSize: size];
  [_owner relayoutSubviewsForSize: size];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  if ([self window] != nil && [self superview] != nil)
    {
      /* GNUstep's setFrame: on the content view bypasses setFrameSize:,
       * so the first layout has to be forced here too. */
      [self setFrame: [[self superview] bounds]];
      [_owner relayoutSubviewsForSize: [self bounds].size];
    }
}

@end

@implementation EauShowcaseWindowController
{
  NSWindow *_window;
  EauShowcaseMainView *_mainView;
  NSScrollView *_sidebarScroll;
  NSTableView *_sidebarTable;
  NSView *_headerView;
  NSTextField *_sectionTitleLabel;
  NSButton *_classicButton;
  NSButton *_compareToggle;
  NSTextField *_violationSummaryLabel;
  NSView *_paneHost;
  NSView *_currentPaneView;
  EauShowcaseMetricsOverlayView *_complianceOverlay;
  NSMutableDictionary *_paneCache;
  NSMutableDictionary *_defaultButtonsByIdentifier;
  NSArray *_sections;
  NSString *_currentIdentifier;
  BOOL _compareEnabled;
  EauTestListDataSource *_listData;
  EauTestWindowController *_classicController;
  NSDrawer *_drawer;
  NSAlert *_sheetAlert;
  NSArray *_outlineRoots;
  NSDictionary *_outlineChildren;
  NSProgressIndicator *_indeterminateBar;
  NSProgressIndicator *_spinner;
  NSTextField *_textFieldForFirstResponder;
}

- (instancetype)init
{
  if ((self = [super init]) != nil)
    {
      _sections = [EauShowcaseSectionRegistry allSections];
      _paneCache = [NSMutableDictionary dictionary];
      _defaultButtonsByIdentifier = [NSMutableDictionary dictionary];
      _listData = [[EauTestListDataSource alloc] init];
      _outlineRoots = @[ @"Applications", @"Documents" ];
      _outlineChildren = @{
        @"Applications": @[ @"Calculator", @"Stickies", @"Terminal" ],
        @"Documents": @[ @"Letter.rtf", @"Budget.csv" ],
      };
      [self buildWindow];
    }
  return self;
}

- (void)showWindow
{
  [_window makeKeyAndOrderFront: nil];
  [_sidebarTable selectRowIndexes: [NSIndexSet indexSetWithIndex: 0]
              byExtendingSelection: NO];
  [self selectSectionWithIdentifier: [[_sections objectAtIndex: 0] identifier]];
}

/* ---------------------------------------------------------------- */
#pragma mark - Window / chrome construction

- (void)buildWindow
{
  _window = [[NSWindow alloc]
    initWithContentRect: NSMakeRect(0, 0, EauShowcaseWindowWidth, EauShowcaseWindowHeight)
              styleMask: NSTitledWindowMask | NSClosableWindowMask
                         | NSMiniaturizableWindowMask | NSResizableWindowMask
                backing: NSBackingStoreBuffered
                  defer: NO];
  [_window setTitle: @"EauTest Showcase"];
  [_window setMinSize: NSMakeSize(700, 440)];
  [_window setReleasedWhenClosed: NO];
  [_window center];

  _mainView = [[EauShowcaseMainView alloc]
    initWithFrame: NSMakeRect(0, 0, EauShowcaseWindowWidth, EauShowcaseWindowHeight)
            owner: self];
  [_window setContentView: _mainView];

  [self buildSidebar];
  [self buildHeader];

  _paneHost = [[NSView alloc] initWithFrame: NSZeroRect];
  [_mainView addSubview: _paneHost];

  _complianceOverlay = [[EauShowcaseMetricsOverlayView alloc] initWithFrame: NSZeroRect];
  [_complianceOverlay setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [_paneHost addSubview: _complianceOverlay];

  [self relayoutSubviewsForSize: [_mainView bounds].size];
}

- (void)buildSidebar
{
  _sidebarScroll = [[NSScrollView alloc] initWithFrame: NSZeroRect];
  [_sidebarScroll setHasVerticalScroller: YES];
  [_sidebarScroll setBorderType: NSBezelBorder];

  _sidebarTable = [[NSTableView alloc] initWithFrame: [[_sidebarScroll contentView] bounds]];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"title"];
  [column setWidth: EauShowcaseSidebarWidth - METRICS_SCROLLBAR_WIDTH];
  [[column headerCell] setStringValue: @"Section"];
  [_sidebarTable addTableColumn: column];
  [_sidebarTable setHeaderView: nil];
  [_sidebarTable setDataSource: (id)self];
  [_sidebarTable setDelegate: (id)self];
  [_sidebarTable setUsesAlternatingRowBackgroundColors: YES];
  [_sidebarScroll setDocumentView: _sidebarTable];

  [_mainView addSubview: _sidebarScroll];
}

- (void)buildHeader
{
  _headerView = [[NSView alloc] initWithFrame: NSZeroRect];

  _sectionTitleLabel = [[NSTextField alloc] initWithFrame: NSZeroRect];
  [_sectionTitleLabel setEditable: NO];
  [_sectionTitleLabel setSelectable: NO];
  [_sectionTitleLabel setBezeled: NO];
  [_sectionTitleLabel setDrawsBackground: NO];
  [_sectionTitleLabel setFont: METRICS_FONT_SYSTEM_BOLD_13];
  [_headerView addSubview: _sectionTitleLabel];

  _classicButton = [EauTestControlFactory pushButtonWithTitle: @"Classic Window"
                                                         target: self
                                                         action: @selector(openClassicWindow:)
                                                    controlSize: NSSmallControlSize];
  [_headerView addSubview: _classicButton];

  _compareToggle = [EauTestControlFactory switchWithTitle: @"Compare with Metrics"
                                                       state: NSOffState enabled: YES];
  [_compareToggle setTarget: self];
  [_compareToggle setAction: @selector(toggleCompareWithMetrics:)];
  [_headerView addSubview: _compareToggle];

  _violationSummaryLabel = [[NSTextField alloc] initWithFrame: NSZeroRect];
  [_violationSummaryLabel setEditable: NO];
  [_violationSummaryLabel setSelectable: NO];
  [_violationSummaryLabel setBezeled: NO];
  [_violationSummaryLabel setDrawsBackground: NO];
  [_violationSummaryLabel setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  [_violationSummaryLabel setAlignment: NSRightTextAlignment];
  [self setViolationSummaryText: @""];
  [_headerView addSubview: _violationSummaryLabel];

  [_mainView addSubview: _headerView];
}

- (void)relayoutSubviewsForSize: (NSSize)size
{
  if (_paneHost == nil)
    return;

  NSRect contentRect = NSMakeRect(
    METRICS_CONTENT_SIDE_MARGIN, METRICS_CONTENT_BOTTOM_MARGIN,
    size.width - 2 * METRICS_CONTENT_SIDE_MARGIN,
    size.height - METRICS_CONTENT_TOP_MARGIN - METRICS_CONTENT_BOTTOM_MARGIN);

  NSRect sidebarFrame = NSMakeRect(NSMinX(contentRect), NSMinY(contentRect),
    EauShowcaseSidebarWidth, NSHeight(contentRect));
  [_sidebarScroll setFrame: sidebarFrame];

  CGFloat containerX = NSMaxX(sidebarFrame) + METRICS_SPACE_16;
  NSRect containerFrame = NSMakeRect(containerX, NSMinY(contentRect),
    NSMaxX(contentRect) - containerX, NSHeight(contentRect));

  NSRect headerFrame = NSMakeRect(NSMinX(containerFrame),
    NSMaxY(containerFrame) - EauShowcaseHeaderHeight,
    NSWidth(containerFrame), EauShowcaseHeaderHeight);
  [_headerView setFrame: headerFrame];
  [self layoutHeaderControls];

  NSRect hostFrame = NSMakeRect(NSMinX(containerFrame), NSMinY(containerFrame),
    NSWidth(containerFrame),
    NSHeight(containerFrame) - EauShowcaseHeaderHeight - METRICS_SPACE_8);
  [_paneHost setFrame: hostFrame];

  if (_currentPaneView != nil)
    [_currentPaneView setFrame: [_paneHost bounds]];
  [_complianceOverlay setFrame: [_paneHost bounds]];

  [self refreshComplianceOverlay];
}

- (void)layoutHeaderControls
{
  NSRect bounds = NSMakeRect(0, 0, NSWidth([_headerView frame]), NSHeight([_headerView frame]));
  CGFloat buttonY = floor((NSHeight(bounds) - METRICS_BUTTON_SMALL_HEIGHT) / 2.0);
  CGFloat toggleY = floor((NSHeight(bounds) - METRICS_RADIO_BUTTON_SIZE) / 2.0);
  CGFloat summaryWidth = 260;
  CGFloat toggleWidth = 176;
  CGFloat classicWidth = 110;

  NSRect summaryFrame = NSMakeRect(NSMaxX(bounds) - summaryWidth, 3, summaryWidth, 17);
  [_violationSummaryLabel setFrame: summaryFrame];

  NSRect toggleFrame = NSMakeRect(NSMinX(summaryFrame) - METRICS_SPACE_12 - toggleWidth,
    toggleY, toggleWidth, METRICS_RADIO_BUTTON_SIZE);
  [_compareToggle setFrame: toggleFrame];

  NSRect classicFrame = NSMakeRect(NSMinX(toggleFrame) - METRICS_SPACE_12 - classicWidth,
    buttonY, classicWidth, METRICS_BUTTON_SMALL_HEIGHT);
  [_classicButton setFrame: classicFrame];

  NSRect titleFrame = NSMakeRect(0, 3, NSMinX(classicFrame) - METRICS_SPACE_12, 17);
  [_sectionTitleLabel setFrame: titleFrame];
}

/* ---------------------------------------------------------------- */
#pragma mark - Sidebar data source / delegate

- (NSInteger)numberOfRowsInTableView: (NSTableView *)tableView
{
  return (NSInteger)[_sections count];
}

- (id)tableView: (NSTableView *)tableView
    objectValueForTableColumn: (NSTableColumn *)column
                          row: (NSInteger)row
{
  return [[_sections objectAtIndex: (NSUInteger)row] title];
}

- (void)tableViewSelectionDidChange: (NSNotification *)notification
{
  NSInteger row = [_sidebarTable selectedRow];
  if (row < 0)
    return;
  EauShowcaseSection *section = [_sections objectAtIndex: (NSUInteger)row];
  [self selectSectionWithIdentifier: [section identifier]];
}

/* ---------------------------------------------------------------- */
#pragma mark - Section selection

- (NSView *)paneForSection: (EauShowcaseSection *)section
{
  NSView *cached = [_paneCache objectForKey: [section identifier]];
  if (cached != nil)
    return cached;

  NSRect hostBounds = [_paneHost bounds];
  SEL builder = [section builderSelector];
  NSView *(*imp)(id, SEL, NSRect) = (NSView *(*)(id, SEL, NSRect))[self methodForSelector: builder];
  NSView *pane = imp(self, builder, hostBounds);
  [_paneCache setObject: pane forKey: [section identifier]];
  return pane;
}

- (void)selectSectionWithIdentifier: (NSString *)identifier
{
  EauShowcaseSection *section = [EauShowcaseSectionRegistry sectionWithIdentifier: identifier];
  if (section == nil)
    return;

  _currentIdentifier = [identifier copy];
  NSView *pane = [self paneForSection: section];
  [pane setFrame: [_paneHost bounds]];

  if (_currentPaneView != nil)
    [_currentPaneView removeFromSuperview];
  [_paneHost addSubview: pane positioned: NSWindowBelow relativeTo: _complianceOverlay];
  _currentPaneView = pane;

  [_sectionTitleLabel setStringValue: [section title]];
  [_window setDefaultButtonCell:
    [[_defaultButtonsByIdentifier objectForKey: identifier] cell]];

  /* GNUstep stops an indeterminate/spinning indicator that is not in a
   * visible window, so (re)start them once their pane is actually shown. */
  [_indeterminateBar startAnimation: nil];
  [_spinner startAnimation: nil];
  if ([identifier isEqualToString: @"textSearch"] && _textFieldForFirstResponder != nil)
    [_window makeFirstResponder: _textFieldForFirstResponder];

  [self refreshComplianceOverlay];
}

/* ---------------------------------------------------------------- */
#pragma mark - Compare with metrics

- (void)toggleCompareWithMetrics: (id)sender
{
  _compareEnabled = ([_compareToggle state] == NSOnState);
  [self refreshComplianceOverlay];
}

- (void)setViolationSummaryText: (NSString *)text
{
  [_violationSummaryLabel setStringValue: text];
}

- (void)refreshComplianceOverlay
{
  if (!_compareEnabled || _currentPaneView == nil)
    {
      [_complianceOverlay setAnnotations: @[]];
      [self setViolationSummaryText: _compareEnabled ? @"No metric violations" : @""];
      return;
    }

  NSArray *annotations = [self violationAnnotationsForPane: _currentPaneView];
  [_complianceOverlay setAnnotations: annotations];
  if ([annotations count] == 0)
    [self setViolationSummaryText: @"No metric violations"];
  else
    [self setViolationSummaryText:
      [NSString stringWithFormat: @"%lu metric violation%@ found",
        (unsigned long)[annotations count], [annotations count] == 1 ? @"" : @"s"]];
}

/* Scans the pane's direct children only - rows a section builder placed
 * with EauTestFormBuilder - against EauMetricsChecker's rules.  Not a
 * generic "walk the whole view tree" pass: a documentation mock-up (the
 * Metrics section's illustrative dialog) is deliberately nested one level
 * deeper so it is never mistaken for a control this scan should judge. */
- (NSArray *)violationAnnotationsForPane: (NSView *)pane
{
  NSMutableArray *controls = [NSMutableArray array];
  for (NSView *view in [pane subviews])
    {
      NSRect frame = [view frame];
      if ([view isKindOfClass: [EauShowcaseMetricsOverlayView class]])
        continue;
      if (EauShowcaseIsExcludedFromScan(view))
        continue;
      if (NSWidth(frame) <= 0 || NSHeight(frame) <= 0)
        continue;
      [controls addObject: [EauMetricsControl controlWithName: EauShowcaseControlName(view)
        frame: frame requiredHeight: EauShowcaseExpectedHeight(view)]];
    }

  NSMutableArray *annotations = [NSMutableArray array];

  for (EauMetricsControl *control in controls)
    {
      EauMetricsViolation *violation = [EauMetricsChecker heightViolationForControl: control];
      if (violation != nil)
        [annotations addObject: [EauShowcaseMetricsAnnotation
          annotationWithRect: [control frame] label: [violation message]
                       color: [NSColor redColor]]];
    }

  /* Group into rows by vertical center (EauTestFormBuilder centers every
   * control in a row on the same line, label included). */
  NSMutableArray *rows = [NSMutableArray array];
  for (EauMetricsControl *control in controls)
    {
      CGFloat centerY = NSMidY([control frame]);
      NSMutableArray *targetRow = nil;
      for (NSMutableArray *row in rows)
        {
          EauMetricsControl *first = [row objectAtIndex: 0];
          if (fabs(NSMidY([first frame]) - centerY) < 2.0)
            {
              targetRow = row;
              break;
            }
        }
      if (targetRow == nil)
        {
          targetRow = [NSMutableArray array];
          [rows addObject: targetRow];
        }
      [targetRow addObject: control];
    }

  for (NSMutableArray *row in rows)
    {
      [row sortUsingComparator: ^NSComparisonResult(id a, id b) {
        CGFloat xa = NSMinX([(EauMetricsControl *)a frame]);
        CGFloat xb = NSMinX([(EauMetricsControl *)b frame]);
        if (xa < xb) return NSOrderedAscending;
        if (xa > xb) return NSOrderedDescending;
        return NSOrderedSame;
      }];
      for (NSUInteger i = 1; i < [row count]; i++)
        {
          EauMetricsControl *prev = [row objectAtIndex: i - 1];
          EauMetricsControl *cur = [row objectAtIndex: i];
          EauMetricsViolation *violation = [EauMetricsChecker
            spacingViolationForControl: cur neighbor: prev verticalLayout: NO];
          if (violation != nil)
            [annotations addObject: [EauShowcaseMetricsAnnotation
              annotationWithRect: NSUnionRect([prev frame], [cur frame])
                           label: [violation message] color: [NSColor redColor]]];
        }
    }

  [rows sortUsingComparator: ^NSComparisonResult(id a, id b) {
    CGFloat ya = NSMidY([(EauMetricsControl *)[(NSArray *)a objectAtIndex: 0] frame]);
    CGFloat yb = NSMidY([(EauMetricsControl *)[(NSArray *)b objectAtIndex: 0] frame]);
    if (ya > yb) return NSOrderedAscending;
    if (ya < yb) return NSOrderedDescending;
    return NSOrderedSame;
  }];
  for (NSUInteger i = 1; i < [rows count]; i++)
    {
      EauMetricsControl *prevLead = [[rows objectAtIndex: i - 1] objectAtIndex: 0];
      EauMetricsControl *curLead = [[rows objectAtIndex: i] objectAtIndex: 0];
      EauMetricsViolation *violation = [EauMetricsChecker
        spacingViolationForControl: curLead neighbor: prevLead verticalLayout: YES];
      if (violation != nil)
        [annotations addObject: [EauShowcaseMetricsAnnotation
          annotationWithRect: NSUnionRect([prevLead frame], [curLead frame])
                       label: [violation message] color: [NSColor redColor]]];
    }

  return annotations;
}

/* ---------------------------------------------------------------- */
#pragma mark - Classic test window

- (void)openClassicWindow: (id)sender
{
  if (_classicController == nil)
    _classicController = [[EauTestWindowController alloc] init];
  [_classicController showWindow];
}

/* ---------------------------------------------------------------- */
#pragma mark - Sample alert / sheet (also used by the Sheets & Alerts stub)

- (NSAlert *)sampleAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText: @"Showcase Alert"];
  [alert setInformativeText: @"Shows how Eau draws an alert panel."];
  [alert addButtonWithTitle: @"OK"];
  [alert addButtonWithTitle: @"Cancel"];
  return alert;
}

- (void)showAlert: (id)sender
{
  [[self sampleAlert] runModal];
}

- (void)showSheet: (id)sender
{
  _sheetAlert = [self sampleAlert];
  [_sheetAlert beginSheetModalForWindow: _window
                          modalDelegate: nil
                         didEndSelector: NULL
                            contextInfo: NULL];
}

/* ---------------------------------------------------------------- */
#pragma mark - Drawer

- (void)toggleDrawer: (id)sender
{
  if ([_drawer state] == NSDrawerClosedState || [_drawer state] == NSDrawerClosingState)
    [_drawer open];
  else
    [_drawer close];
}

/* ---------------------------------------------------------------- */
#pragma mark - Outline view data source (Tables & Outline Views section)

- (NSInteger)outlineView: (NSOutlineView *)outlineView numberOfChildrenOfItem: (id)item
{
  NSArray *children = (item == nil) ? _outlineRoots : [_outlineChildren objectForKey: item];
  return (NSInteger)[children count];
}

- (BOOL)outlineView: (NSOutlineView *)outlineView isItemExpandable: (id)item
{
  return [_outlineChildren objectForKey: item] != nil;
}

- (id)outlineView: (NSOutlineView *)outlineView child: (NSInteger)index ofItem: (id)item
{
  NSArray *children = (item == nil) ? _outlineRoots : [_outlineChildren objectForKey: item];
  return [children objectAtIndex: (NSUInteger)index];
}

- (id)outlineView: (NSOutlineView *)outlineView
    objectValueForTableColumn: (NSTableColumn *)column
                       byItem: (id)item
{
  return item;
}

/* ---------------------------------------------------------------- */
#pragma mark - Section builders (one per control family)

- (NSView *)buildButtonsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  [form addRowWithLabel: @"Push (Enabled):"
                controls: @[ ShowcaseButton(@"Rounded", nil, NULL, NSRegularControlSize) ]];

  NSButton *defaultButton = ShowcaseButton(@"Default", nil, NULL, NSRegularControlSize);
  [defaultButton setKeyEquivalent: @"\r"];
  [form addRowWithLabel: @"Push (Key/Default):" controls: @[ defaultButton ]];
  [_defaultButtonsByIdentifier setObject: defaultButton forKey: @"buttons"];

  NSButton *disabledButton = ShowcaseButton(@"Disabled", nil, NULL, NSRegularControlSize);
  [disabledButton setEnabled: NO];
  [form addRowWithLabel: @"Push (Disabled):" controls: @[ disabledButton ]];

  NSButton *smallEnabled = ShowcaseButton(@"Small", nil, NULL, NSSmallControlSize);
  NSButton *smallDisabled = ShowcaseButton(@"Small Disabled", nil, NULL, NSSmallControlSize);
  [smallDisabled setEnabled: NO];
  [form addRowWithLabel: @"Push (Small):" controls: @[ smallEnabled, smallDisabled ]];

  NSButton *disclosure = [EauTestControlFactory bezelButtonWithStyle: NSDisclosureBezelStyle side: 13];
  NSButton *help = [EauTestControlFactory bezelButtonWithStyle: NSHelpButtonBezelStyle side: 21];
  [form addRowWithLabel: @"Bevel (Disclosure, Help):" controls: @[ disclosure, help ]];

  return pane;
}

- (NSView *)buildChecksRadiosSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  [form addRowWithLabel: @"Checkbox (On/Off/Mixed):" controls: @[
    ShowcaseSwitch(@"On", NSOnState, YES, NSRegularControlSize),
    ShowcaseSwitch(@"Off", NSOffState, YES, NSRegularControlSize),
    ShowcaseSwitch(@"Mixed", NSMixedState, YES, NSRegularControlSize) ]];

  [form addRowWithLabel: @"Checkbox (Disabled):" controls: @[
    ShowcaseSwitch(@"On", NSOnState, NO, NSRegularControlSize),
    ShowcaseSwitch(@"Off", NSOffState, NO, NSRegularControlSize) ]];

  [form addRowWithLabel: @"Checkbox (Small):" controls: @[
    ShowcaseSwitch(@"On", NSOnState, YES, NSSmallControlSize),
    ShowcaseSwitch(@"Off", NSOffState, YES, NSSmallControlSize) ]];

  NSButtonCell *radioPrototype = [[NSButtonCell alloc] init];
  [radioPrototype setButtonType: NSRadioButton];
  NSMatrix *radios = [[NSMatrix alloc]
    initWithFrame: NSMakeRect(0, 0, 3 * 90, METRICS_RADIO_BUTTON_SIZE)
             mode: NSRadioModeMatrix
        prototype: radioPrototype
     numberOfRows: 1
  numberOfColumns: 3];
  [radios setCellSize: NSMakeSize(90, METRICS_RADIO_BUTTON_SIZE)];
  NSArray *titles = @[ @"First", @"Second", @"Third" ];
  for (NSUInteger i = 0; i < [titles count]; i++)
    [[radios cellAtRow: 0 column: (NSInteger)i] setTitle: [titles objectAtIndex: i]];
  [radios selectCellAtRow: 0 column: 0];
  EauShowcaseTag(radios, @"radio group", METRICS_RADIO_BUTTON_SIZE);
  [form addRowWithLabel: @"Radio (Selected):" controls: @[ radios ]];

  NSMatrix *disabledRadios = [[NSMatrix alloc]
    initWithFrame: NSMakeRect(0, 0, 2 * 90, METRICS_RADIO_BUTTON_SIZE)
             mode: NSRadioModeMatrix
        prototype: radioPrototype
     numberOfRows: 1
  numberOfColumns: 2];
  [disabledRadios setCellSize: NSMakeSize(90, METRICS_RADIO_BUTTON_SIZE)];
  [[disabledRadios cellAtRow: 0 column: 0] setTitle: @"First"];
  [[disabledRadios cellAtRow: 0 column: 1] setTitle: @"Second"];
  [disabledRadios setEnabled: NO];
  EauShowcaseTag(disabledRadios, @"disabled radio group", METRICS_RADIO_BUTTON_SIZE);
  [form addRowWithLabel: @"Radio (Disabled):" controls: @[ disabledRadios ]];

  return pane;
}

- (NSView *)buildPopUpsCombosSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSPopUpButton *popUp = [[NSPopUpButton alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT) pullsDown: NO];
  [popUp addItemsWithTitles: @[ @"Small", @"Medium", @"Large" ]];
  [form addRowWithLabel: @"Pop-Up (Enabled):" controls: @[ popUp ]];

  NSPopUpButton *popUpDisabled = [[NSPopUpButton alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT) pullsDown: NO];
  [popUpDisabled addItemsWithTitles: @[ @"Small", @"Medium", @"Large" ]];
  [popUpDisabled setEnabled: NO];
  [form addRowWithLabel: @"Pop-Up (Disabled):" controls: @[ popUpDisabled ]];

  NSPopUpButton *pullDown = [[NSPopUpButton alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT) pullsDown: YES];
  [pullDown addItemsWithTitles: @[ @"Actions", @"Rename", @"Duplicate" ]];
  [form addRowWithLabel: @"Pull-Down (Enabled):" controls: @[ pullDown ]];

  NSComboBox *combo = [EauTestControlFactory inputFieldOfClass: [NSComboBox class] width: 160];
  [combo addItemsWithObjectValues: @[ @"Red", @"Green", @"Blue" ]];
  [combo selectItemAtIndex: 0];
  [combo setStringValue: @"Red"];
  NSComboBox *comboDisabled = [EauTestControlFactory inputFieldOfClass: [NSComboBox class] width: 160];
  [comboDisabled addItemsWithObjectValues: @[ @"Red", @"Green", @"Blue" ]];
  [comboDisabled setStringValue: @"Red"];
  [comboDisabled setEnabled: NO];
  [form addRowWithLabel: @"Combo Box (Enabled/Disabled):" controls: @[ combo, comboDisabled ]];

  return pane;
}

- (NSView *)buildTextSearchSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSTextField *field = ShowcaseInputField([NSTextField class], @"text field", EauShowcaseFieldWidth);
  [field setStringValue: @"Key / first responder"];
  [form addRowWithLabel: @"Text Field (Key):" controls: @[ field ]];

  NSTextField *disabledField = ShowcaseInputField([NSTextField class], @"disabled field", EauShowcaseFieldWidth);
  [disabledField setStringValue: @"Disabled"];
  [disabledField setEnabled: NO];
  [form addRowWithLabel: @"Text Field (Disabled):" controls: @[ disabledField ]];

  NSSecureTextField *secure = ShowcaseInputField([NSSecureTextField class], @"secure field", EauShowcaseFieldWidth);
  [secure setStringValue: @"secret"];
  [form addRowWithLabel: @"Secure Field:" controls: @[ secure ]];

  NSSearchField *search = [[NSSearchField alloc] initWithFrame:
    [EauTestControlFactory inputFieldFrameWithWidth: EauShowcaseFieldWidth]];
  EauShowcaseTag(search, @"search field", METRICS_TEXT_INPUT_FIELD_HEIGHT);
  [form addRowWithLabel: @"Search Field:" controls: @[ search ]];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 80)];
  [scroll setHasVerticalScroller: YES];
  [scroll setBorderType: NSBezelBorder];
  NSTextView *textView = [[NSTextView alloc] initWithFrame:
    NSMakeRect(0, 0, [scroll contentSize].width, [scroll contentSize].height)];
  [textView setAutoresizingMask: NSViewWidthSizable];
  [textView setString: @"A multi-line text view.\nScrolls once the text grows "
    @"beyond its height.\nThird line.\nFourth line."];
  [scroll setDocumentView: textView];
  [form addRowWithLabel: @"Text View:" controls: @[ scroll ]];

  _textFieldForFirstResponder = field;
  return pane;
}

- (NSView *)buildSlidersSteppersSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSSlider *slider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 21)];
  [slider setMinValue: 0];
  [slider setMaxValue: 100];
  [slider setDoubleValue: 40];
  [form addRowWithLabel: @"Slider (Enabled):" controls: @[ slider ]];

  NSSlider *disabledSlider = [[NSSlider alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 21)];
  [disabledSlider setMinValue: 0];
  [disabledSlider setMaxValue: 100];
  [disabledSlider setDoubleValue: 65];
  [disabledSlider setEnabled: NO];
  [form addRowWithLabel: @"Slider (Disabled):" controls: @[ disabledSlider ]];

  NSTextField *stepperValue = ShowcaseValueField(@"5", 50);
  NSStepper *stepper = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 15, 22)];
  [stepper setMinValue: 0];
  [stepper setMaxValue: 10];
  [stepper setIntegerValue: 5];
  [stepper setTarget: stepperValue];
  [stepper setAction: @selector(takeIntegerValueFrom:)];
  [form addRowWithLabel: @"Stepper (Enabled):" controls: @[ stepperValue, stepper ]];

  NSTextField *disabledStepperValue = ShowcaseValueField(@"3", 50);
  [disabledStepperValue setEnabled: NO];
  NSStepper *disabledStepper = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 15, 22)];
  [disabledStepper setIntegerValue: 3];
  [disabledStepper setEnabled: NO];
  [form addRowWithLabel: @"Stepper (Disabled):" controls: @[ disabledStepperValue, disabledStepper ]];

  return pane;
}

- (NSView *)buildProgressLevelSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSProgressIndicator *determinate = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 20)];
  [determinate setIndeterminate: NO];
  [determinate setDoubleValue: 60];
  [form addRowWithLabel: @"Progress (Determinate):" controls: @[ determinate ]];

  NSProgressIndicator *indeterminate = [[NSProgressIndicator alloc]
    initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 20)];
  [indeterminate setIndeterminate: YES];
  [form addRowWithLabel: @"Progress (Indeterminate):" controls: @[ indeterminate ]];
  _indeterminateBar = indeterminate;

  NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame: NSMakeRect(0, 0, 32, 32)];
  [spinner setStyle: NSProgressIndicatorSpinningStyle];
  [form addRowWithLabel: @"Progress (Spinning):" controls: @[ spinner ]];
  _spinner = spinner;

  NSLevelIndicator *level = [[NSLevelIndicator alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 20)];
  [level setMinValue: 0];
  [level setMaxValue: 10];
  [level setDoubleValue: 6];
  [form addRowWithLabel: @"Level Indicator (Enabled):" controls: @[ level ]];

  NSLevelIndicator *disabledLevel = [[NSLevelIndicator alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 20)];
  [disabledLevel setMinValue: 0];
  [disabledLevel setMaxValue: 10];
  [disabledLevel setDoubleValue: 3];
  [disabledLevel setEnabled: NO];
  [form addRowWithLabel: @"Level Indicator (Disabled):" controls: @[ disabledLevel ]];

  return pane;
}

- (NSView *)buildSegmentedTabsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSSegmentedControl *segments = [[NSSegmentedControl alloc]
    initWithFrame: NSMakeRect(0, 0, 240, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
  [segments setSegmentCount: 3];
  NSArray *titles = @[ @"Icons", @"List", @"Columns" ];
  for (NSUInteger i = 0; i < [titles count]; i++)
    {
      [segments setLabel: [titles objectAtIndex: i] forSegment: (NSInteger)i];
      [segments setWidth: 80 forSegment: (NSInteger)i];
    }
  [segments setSelectedSegment: 1];
  [form addRowWithLabel: @"Segmented (Selected):" controls: @[ segments ]];

  NSSegmentedControl *disabledSegments = [[NSSegmentedControl alloc]
    initWithFrame: NSMakeRect(0, 0, 160, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
  [disabledSegments setSegmentCount: 2];
  [disabledSegments setLabel: @"On" forSegment: 0];
  [disabledSegments setLabel: @"Off" forSegment: 1];
  [disabledSegments setWidth: 80 forSegment: 0];
  [disabledSegments setWidth: 80 forSegment: 1];
  [disabledSegments setEnabled: NO];
  [form addRowWithLabel: @"Segmented (Disabled):" controls: @[ disabledSegments ]];

  NSTabView *tabs = [[NSTabView alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 90)];
  NSTabViewItem *item1 = [[NSTabViewItem alloc] initWithIdentifier: @"one"];
  [item1 setLabel: @"One"];
  [item1 setView: [[NSView alloc] initWithFrame: [tabs contentRect]]];
  NSTabViewItem *item2 = [[NSTabViewItem alloc] initWithIdentifier: @"two"];
  [item2 setLabel: @"Two"];
  [item2 setView: [[NSView alloc] initWithFrame: [tabs contentRect]]];
  [tabs addTabViewItem: item1];
  [tabs addTabViewItem: item2];
  [form addRowWithLabel: @"Tab View:" controls: @[ tabs ]];

  return pane;
}

- (NSView *)buildBoxesGroupsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSBox *titledBox = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 60)];
  [titledBox setTitle: @"Titled Box"];
  [form addRowWithLabel: @"Box (Titled):" controls: @[ titledBox ]];

  NSBox *groove = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 2)];
  [groove setBoxType: NSBoxSeparator];
  [form addRowWithLabel: @"Box (Separator):" controls: @[ groove ]];

  return pane;
}

- (NSView *)buildTablesOutlinesSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSScrollView *tableScroll = [[NSScrollView alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 110)];
  [tableScroll setHasVerticalScroller: YES];
  [tableScroll setBorderType: NSBezelBorder];
  NSTableView *table = [[NSTableView alloc] initWithFrame: [[tableScroll contentView] bounds]];
  for (NSString *identifier in @[ @"name", @"kind" ])
    {
      NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: identifier];
      [[column headerCell] setStringValue: [identifier capitalizedString]];
      [column setWidth: (EauShowcaseFieldWidth - METRICS_SCROLLBAR_WIDTH) / 2 - 4];
      [table addTableColumn: column];
    }
  [table setDataSource: (id)_listData];
  [table setUsesAlternatingRowBackgroundColors: YES];
  [tableScroll setDocumentView: table];
  [form addRowWithLabel: @"Table:" controls: @[ tableScroll ]];

  NSScrollView *outlineScroll = [[NSScrollView alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 110)];
  [outlineScroll setHasVerticalScroller: YES];
  [outlineScroll setBorderType: NSBezelBorder];
  NSOutlineView *outline = [[NSOutlineView alloc] initWithFrame: [[outlineScroll contentView] bounds]];
  NSTableColumn *outlineColumn = [[NSTableColumn alloc] initWithIdentifier: @"item"];
  [[outlineColumn headerCell] setStringValue: @"Item"];
  [outlineColumn setWidth: EauShowcaseFieldWidth - METRICS_SCROLLBAR_WIDTH - 4];
  [outline addTableColumn: outlineColumn];
  [outline setOutlineTableColumn: outlineColumn];
  [outline setDataSource: (id)self];
  [outlineScroll setDocumentView: outline];
  [outline reloadData];
  [outline expandItem: @"Applications"];
  [form addRowWithLabel: @"Outline View:" controls: @[ outlineScroll ]];

  return pane;
}

- (NSView *)buildBrowsersSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSBrowser *browser = [[NSBrowser alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 160)];
  [browser setMaxVisibleColumns: 2];
  [browser setDelegate: (id)_listData];
  [browser loadColumnZero];
  [form addRowWithLabel: @"Browser:" controls: @[ browser ]];

  return pane;
}

- (NSView *)buildScrollSplitSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 90)];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setBorderType: NSBezelBorder];
  NSView *documentView = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 700, 300)];
  [scroll setDocumentView: documentView];
  [form addRowWithLabel: @"Scroll View:" controls: @[ scroll ]];

  NSSplitView *split = [[NSSplitView alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 90)];
  NSView *left = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 120, 90)];
  NSView *right = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 120, 90)];
  [split addSubview: left];
  [split addSubview: right];
  [form addRowWithLabel: @"Split View:" controls: @[ split ]];

  return pane;
}

- (NSView *)buildDisclosureToolbarsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSButton *closed = [EauTestControlFactory bezelButtonWithStyle: NSDisclosureBezelStyle side: 13];
  [closed setState: NSOffState];
  NSButton *open = [EauTestControlFactory bezelButtonWithStyle: NSDisclosureBezelStyle side: 13];
  [open setState: NSOnState];
  [form addRowWithLabel: @"Disclosure (Closed/Open):" controls: @[ closed, open ]];

  /* Toolbar-style bevel row: AppearanceMetrics calls for 8px between
   * toolbar bevel buttons, distinct from the 12px push-button spacing. */
  NSBox *bar = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, EauShowcaseFieldWidth, 32)];
  [bar setBoxType: NSBoxPrimary];
  [bar setTitlePosition: NSNoTitle];
  EauShowcaseExcludeFromScan(bar);
  NSView *barContent = [bar contentView];
  CGFloat x = 4;
  NSArray *toolbarLabels = @[ @"A", @"B", @"C" ];
  for (NSString *label in toolbarLabels)
    {
      NSButton *bevel = [EauTestControlFactory bezelButtonWithStyle: NSRegularSquareBezelStyle side: 24];
      [bevel setTitle: label];
      [bevel setFrameOrigin: NSMakePoint(x, 3)];
      [barContent addSubview: bevel];
      x += 24 + METRICS_SPACE_8;
    }
  [form addRowWithLabel: @"Tool Bar (8px apart):" controls: @[ bar ]];

  return pane;
}

- (NSView *)buildSheetsAlertsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSTextField *note = [[NSTextField alloc] initWithFrame:
    NSMakeRect(0, 0, EauShowcaseFieldWidth, 34)];
  [note setEditable: NO];
  [note setSelectable: NO];
  [note setBezeled: NO];
  [note setDrawsBackground: NO];
  [note setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  [note setStringValue: @"Stub: a themed sheet transition lands separately. "
    @"These buttons already exercise the real NSAlert/sheet paths that "
    @"work will attach to."];
  EauShowcaseExcludeFromScan(note);
  [form addRowWithLabel: @"Sheets & Alerts (stub):" controls: @[ note ]];

  [form addRowWithLabel: @"Alert (Modal):" controls: @[
    ShowcaseButton(@"Show Alert", self, @selector(showAlert:), NSRegularControlSize) ]];

  [form addRowWithLabel: @"Sheet (Attached):" controls: @[
    ShowcaseButton(@"Show Sheet", self, @selector(showSheet:), NSRegularControlSize) ]];

  return pane;
}

- (NSView *)buildDrawersSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  if (_drawer == nil)
    {
      _drawer = [[NSDrawer alloc] initWithContentSize: NSMakeSize(160, 200)
                                     preferredEdge: NSMaxXEdge];
      [_drawer setParentWindow: _window];
      NSTextField *drawerLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(12, 90, 136, 20)];
      [drawerLabel setEditable: NO];
      [drawerLabel setSelectable: NO];
      [drawerLabel setBezeled: NO];
      [drawerLabel setDrawsBackground: NO];
      [drawerLabel setStringValue: @"Drawer content"];
      NSView *drawerContent = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 160, 200)];
      [drawerContent addSubview: drawerLabel];
      [_drawer setContentView: drawerContent];
    }

  [form addRowWithLabel: @"Drawer (Toggle):" controls: @[
    ShowcaseButton(@"Open/Close Drawer", self, @selector(toggleDrawer:), NSRegularControlSize) ]];

  return pane;
}

- (NSView *)buildColorDateSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  EauTestFormBuilder *form = [[EauTestFormBuilder alloc] initWithView: pane];

  NSColorWell *well = [[NSColorWell alloc] initWithFrame: NSMakeRect(0, 0, 52, 26)];
  [well setColor: [NSColor colorWithCalibratedRed: 0.2 green: 0.5 blue: 0.9 alpha: 1.0]];
  NSColorWell *disabledWell = [[NSColorWell alloc] initWithFrame: NSMakeRect(0, 0, 52, 26)];
  [disabledWell setColor: [NSColor colorWithCalibratedRed: 0.9 green: 0.3 blue: 0.2 alpha: 1.0]];
  [disabledWell setEnabled: NO];
  [form addRowWithLabel: @"Colour Well (Enabled/Disabled):" controls: @[ well, disabledWell ]];

  NSDatePicker *textualDate = [[NSDatePicker alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
  [[textualDate cell] setDatePickerStyle: NSTextFieldDatePickerStyle];
  [textualDate setDateValue: [NSDate date]];
  [form addRowWithLabel: @"Date Picker (Textual):" controls: @[ textualDate ]];

  NSDatePicker *disabledDate = [[NSDatePicker alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
  [[disabledDate cell] setDatePickerStyle: NSTextFieldDatePickerStyle];
  [disabledDate setDateValue: [NSDate date]];
  [disabledDate setEnabled: NO];
  [form addRowWithLabel: @"Date Picker (Disabled):" controls: @[ disabledDate ]];

  return pane;
}

- (NSView *)buildMetricsSection: (NSRect)bounds
{
  NSView *pane = NewPane(bounds);
  const CGFloat top = NSHeight(bounds) - METRICS_CONTENT_TOP_MARGIN;

  NSTextField *heading = [[NSTextField alloc] initWithFrame:
    NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, top - 34, NSWidth(bounds) - 2 * METRICS_CONTENT_SIDE_MARGIN, 34)];
  [heading setEditable: NO];
  [heading setSelectable: NO];
  [heading setBezeled: NO];
  [heading setDrawsBackground: NO];
  [heading setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  [heading setStringValue: @"The translucent bands below are AppearanceMetrics.h's spacing "
    @"and sizing rules, drawn on a mock dialog the way this documentation describes them."];
  EauShowcaseExcludeFromScan(heading);
  [pane addSubview: heading];

  /* A mock dialog: two buttons in HIG order, a labeled field, and a group
   * box - one instance of nearly every rule this file documents. */
  NSRect mockFrame = NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, top - 34 - METRICS_SPACE_16 - 230,
    460, 230);
  NSBox *mockDialog = [[NSBox alloc] initWithFrame: mockFrame];
  [mockDialog setTitlePosition: NSNoTitle];
  [mockDialog setBoxType: NSBoxPrimary];
  EauShowcaseExcludeFromScan(mockDialog);
  NSView *mockContent = [mockDialog contentView];
  NSRect mockBounds = [mockContent bounds];

  NSButton *ok = [EauTestControlFactory pushButtonWithTitle: @"OK" target: nil action: NULL];
  [ok setFrameOrigin: NSMakePoint(
    NSMaxX(mockBounds) - METRICS_CONTENT_SIDE_MARGIN - METRICS_BUTTON_MIN_WIDTH,
    METRICS_CONTENT_BOTTOM_MARGIN)];
  [mockContent addSubview: ok];
  NSButton *cancel = [EauTestControlFactory pushButtonWithTitle: @"Cancel" target: nil action: NULL];
  [cancel setFrameOrigin: NSMakePoint(
    NSMinX([ok frame]) - METRICS_BUTTON_HORIZ_INTERSPACE - METRICS_BUTTON_MIN_WIDTH,
    METRICS_CONTENT_BOTTOM_MARGIN)];
  [mockContent addSubview: cancel];

  NSTextField *fieldLabel = [[NSTextField alloc] initWithFrame:
    NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, NSMaxY(mockBounds) - METRICS_CONTENT_TOP_MARGIN - 17,
               90, 17)];
  [fieldLabel setEditable: NO];
  [fieldLabel setSelectable: NO];
  [fieldLabel setBezeled: NO];
  [fieldLabel setDrawsBackground: NO];
  [fieldLabel setStringValue: @"Name:"];
  [mockContent addSubview: fieldLabel];
  NSTextField *field = [EauTestControlFactory inputFieldOfClass: [NSTextField class] width: 200];
  [field setFrameOrigin: NSMakePoint(NSMaxX([fieldLabel frame]) + METRICS_SPACE_8,
    NSMinY([fieldLabel frame]) - floor((METRICS_TEXT_INPUT_FIELD_HEIGHT - 17) / 2.0))];
  [mockContent addSubview: field];

  NSBox *group = [[NSBox alloc] initWithFrame: NSMakeRect(
    METRICS_CONTENT_SIDE_MARGIN, METRICS_CONTENT_BOTTOM_MARGIN + METRICS_BUTTON_HEIGHT + METRICS_SPACE_16,
    NSWidth(mockBounds) - 2 * METRICS_CONTENT_SIDE_MARGIN, 60)];
  [group setTitle: @"Options"];
  NSView *groupContent = [group contentView];
  NSButton *groupCheck1 = [EauTestControlFactory switchWithTitle: @"Alpha" state: NSOnState enabled: YES];
  [groupCheck1 setFrameOrigin: NSMakePoint(METRICS_SPACE_16, 4)];
  NSButton *groupCheck2 = [EauTestControlFactory switchWithTitle: @"Beta" state: NSOffState enabled: YES];
  [groupCheck2 setFrameOrigin: NSMakePoint(NSMaxX([groupCheck1 frame]) + METRICS_SPACE_12, 4)];
  [groupContent addSubview: groupCheck1];
  [groupContent addSubview: groupCheck2];
  [mockContent addSubview: group];

  [pane addSubview: mockDialog];

  EauShowcaseMetricsOverlayView *ruler = [[EauShowcaseMetricsOverlayView alloc]
    initWithFrame: mockFrame];
  EauShowcaseExcludeFromScan(ruler);
  NSMutableArray *annotations = [NSMutableArray array];
  NSColor *marginColor = [NSColor colorWithCalibratedRed: 0.2 green: 0.4 blue: 0.9 alpha: 1.0];
  NSColor *gapColor = [NSColor colorWithCalibratedRed: 0.1 green: 0.6 blue: 0.3 alpha: 1.0];
  NSColor *insetColor = [NSColor colorWithCalibratedRed: 0.6 green: 0.3 blue: 0.7 alpha: 1.0];

  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(0, NSMaxY(mockBounds) - METRICS_CONTENT_TOP_MARGIN, NSWidth(mockBounds), METRICS_CONTENT_TOP_MARGIN)
                 label: @"15px top margin" color: marginColor]];
  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(0, 0, METRICS_CONTENT_SIDE_MARGIN, NSHeight(mockBounds))
                 label: @"24px side margin" color: marginColor]];
  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(0, 0, NSWidth(mockBounds), METRICS_CONTENT_BOTTOM_MARGIN)
                 label: @"20px bottom margin" color: marginColor]];
  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(NSMaxX([cancel frame]), NSMinY([cancel frame]),
                                    NSMinX([ok frame]) - NSMaxX([cancel frame]), METRICS_BUTTON_HEIGHT)
                 label: @"12px button gap" color: gapColor]];
  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(NSMaxX([fieldLabel frame]), NSMinY([fieldLabel frame]),
                                    NSMinX([field frame]) - NSMaxX([fieldLabel frame]), 17)
                 label: @"8px label gap" color: gapColor]];
  [annotations addObject: [EauShowcaseMetricsAnnotation
    annotationWithRect: NSMakeRect(NSMinX([group frame]), NSMinY([group frame]),
                                    METRICS_SPACE_16, NSHeight([group frame]))
                 label: @"16px group-box inset" color: insetColor]];
  [ruler setAnnotations: annotations];
  [pane addSubview: ruler];

  /* Deliberate violation, left as a direct child of the pane (not nested
   * in the mock dialog) so "Compare with metrics" has something real to
   * catch: these two buttons sit 10px apart, which is not in the
   * canonical {2,4,6,8,12,16,20,24} spacing set. */
  NSTextField *demoLabel = [[NSTextField alloc] initWithFrame:
    NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, METRICS_CONTENT_BOTTOM_MARGIN + 40, 460, 17)];
  [demoLabel setEditable: NO];
  [demoLabel setSelectable: NO];
  [demoLabel setBezeled: NO];
  [demoLabel setDrawsBackground: NO];
  [demoLabel setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  [demoLabel setStringValue: @"Demo violation below (10px gap) - toggle Compare with Metrics to flag it:"];
  EauShowcaseExcludeFromScan(demoLabel);
  [pane addSubview: demoLabel];

  NSButton *demoA = ShowcaseButton(@"A", nil, NULL, NSSmallControlSize);
  [demoA setFrameOrigin: NSMakePoint(METRICS_CONTENT_SIDE_MARGIN, METRICS_CONTENT_BOTTOM_MARGIN)];
  NSButton *demoB = ShowcaseButton(@"B", nil, NULL, NSSmallControlSize);
  [demoB setFrameOrigin: NSMakePoint(NSMaxX([demoA frame]) + 10, METRICS_CONTENT_BOTTOM_MARGIN)];
  [pane addSubview: demoA];
  [pane addSubview: demoB];

  return pane;
}

@end
