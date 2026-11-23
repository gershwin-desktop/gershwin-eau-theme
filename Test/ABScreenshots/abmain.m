/* abharness - A/B pixel harness for Eau.
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * Drives the EauTest fixture and showcase (sources shared with ../) through
 * a fixed script and screenshots every state into $AB_OUT.  The same binary
 * runs against both themes being compared, so any pixel difference comes
 * from the theme or the behaviors bundle, not from the harness.  Run it
 * through ab-compare.sh, which sets up the display, scales and comparison.
 * AB_QUICK=1 skips all mouse interaction so the Tab focus ring stays on for
 * the panels and sheets. */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>
#import <objc/runtime.h>
#include <X11/Xlib.h>
#include <math.h>
#include <stdlib.h>
#include <unistd.h>

#import "EauShowcaseWindowController.h"
#import "EauShowcaseSectionRegistry.h"
#import "EauTestWindowController.h"

extern int eau_orig_main(int argc, const char **argv);

static NSString *outDir;
static NSMutableArray *log_;

/* ---- determinism: quantized clock (3.0 s steps = METRICS_PULSE_DURATION) -- */
static IMP origTISRD;
static NSTimeInterval q_tisrd(id self, SEL _cmd)
{
  NSTimeInterval t = ((NSTimeInterval (*)(id, SEL))origTISRD)(self, _cmd);
  return floor(t / 3.0) * 3.0;
}
static void noop_blink(id self, SEL _cmd, id t) {}

static void installDeterminism(void)
{
  Method m = class_getClassMethod([NSDate class], @selector(timeIntervalSinceReferenceDate));
  origTISRD = method_setImplementation(m, (IMP)q_tisrd);
  Method b = class_getInstanceMethod([NSTextView class], NSSelectorFromString(@"_blink:"));
  if (b) method_setImplementation(b, (IMP)noop_blink);
}

static void resetSpinners(NSView *v)
{
  if ([v isKindOfClass: [NSProgressIndicator class]])
    {
      Ivar iv = class_getInstanceVariable([NSProgressIndicator class], "_count");
      if (iv)
        *(int *)((char *)(__bridge void *)v + ivar_getOffset(iv)) = 0;
      [v setNeedsDisplay: YES];
    }
  if ([v isKindOfClass: [NSDatePicker class]])
    [(NSDatePicker *)v setDateValue: [NSDate dateWithString: @"2026-01-02 10:20:30 +0000"]];
  for (NSView *s in [v subviews])
    resetSpinners(s);
}

/* ---- metrics: geometry of every view, for the WM vs no-WM comparison ----
 * One tab-separated line per item, all rects in device pixels relative to
 * the window's content view, so window placement and decorations (which a
 * window manager owns) drop out and only the theme's own layout remains:
 *   window-key  path  class  kind  x y w h
 * kind: content (content view size), frame (a view), title (a text cell's
 * text rect, which fixes where its baseline sits), editor (the field editor
 * of the control being edited). */
static void dumpRect(NSMutableString *out, NSString *key, NSString *path, NSString *cls,
                     NSString *kind, NSRect r, CGFloat k)
{
  [out appendFormat: @"%@\t%@\t%@\t%@\t%.2f %.2f %.2f %.2f\n", key, path, cls, kind,
       r.origin.x * k, r.origin.y * k, r.size.width * k, r.size.height * k];
}

static void dumpView(NSMutableString *out, NSString *key, NSString *path, NSView *v,
                     NSView *cv, CGFloat k)
{
  NSString *cls = NSStringFromClass([v class]);
  dumpRect(out, key, path, cls, @"frame", [v convertRect: [v bounds] toView: cv], k);
  if ([v isKindOfClass: [NSControl class]]
      && [[(NSControl *)v cell] isKindOfClass: [NSTextFieldCell class]])
    {
      NSRect t = [[(NSControl *)v cell] titleRectForBounds: [v bounds]];
      dumpRect(out, key, path, cls, @"title", [v convertRect: t toView: cv], k);
      NSText *ed = [(NSControl *)v currentEditor];
      if (ed != nil)
        dumpRect(out, key, path, NSStringFromClass([ed class]), @"editor",
                 [ed convertRect: [ed bounds] toView: cv], k);
    }
  NSUInteger i = 0;
  for (NSView *sv in [v subviews])
    {
      /* A field editor is reported through its control above; its clip view
       * and scroller layout follow from that. */
      if (![sv isKindOfClass: [NSText class]])
        dumpView(out, key, [NSString stringWithFormat: @"%@.%lu", path, (unsigned long)i],
                 sv, cv, k);
      i++;
    }
}

static void dumpMetrics(NSString *name)
{
  NSMutableString *out = [NSMutableString string];
  NSMutableDictionary *seen = [NSMutableDictionary dictionary];
  for (NSWindow *w in [NSApp windows])
    {
      NSView *cv = [w contentView];
      if (![w isVisible] || cv == nil)
        continue;
      /* Windows of one class and title (menu panels) are told apart by size:
       * their order in -windows differs from run to run. */
      NSSize size = [cv bounds].size;
      NSString *base = [NSString stringWithFormat: @"%@:%@:%.0fx%.0f", NSStringFromClass([w class]),
                                 [[w title] stringByReplacingOccurrencesOfString: @"\t" withString: @" "],
                                 size.width, size.height];
      NSUInteger n = [[seen objectForKey: base] unsignedIntegerValue];
      [seen setObject: @(n + 1) forKey: base];
      NSString *key = [NSString stringWithFormat: @"%@#%lu", base, (unsigned long)n];
      /* Device pixels per point. */
      CGFloat k = [cv convertSize: NSMakeSize(1, 1) toView: nil].width;
      dumpRect(out, key, @"-", NSStringFromClass([cv class]), @"content", [cv bounds], k);
      dumpView(out, key, @"0", cv, cv, k);
    }
  [out writeToFile: [outDir stringByAppendingPathComponent:
                              [name stringByAppendingPathExtension: @"metrics"]]
        atomically: YES encoding: NSUTF8StringEncoding error: NULL];
}

@interface ABDriver : NSObject
@property (strong) id appDelegate;
@property (strong) EauShowcaseWindowController *showcase;
@end

static ABDriver *driver;

static NSArray *allModes(void)
{
  return @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ];
}

@implementation ABDriver

- (void)onMain: (SEL)sel with: (id)arg
{
  [self performSelectorOnMainThread: sel withObject: arg waitUntilDone: YES modes: allModes()];
}
- (void)onMainAsync: (SEL)sel with: (id)arg
{
  [self performSelectorOnMainThread: sel withObject: arg waitUntilDone: NO modes: allModes()];
}

/* ---- main-thread steps ---- */
- (void)normalizeAndDisplay
{
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible])
      {
        resetSpinners([[w contentView] superview] ?: [w contentView]);
        [w display];
        [w flushWindow];
      }
  /* no flushGraphics */
  {
    id srv = GSCurrentServer();
    Method xm = class_getInstanceMethod([srv class], @selector(xDisplay));
    if (xm)
      XSync(((Display *(*)(id, SEL))method_getImplementation(xm))(srv, @selector(xDisplay)), False);
    usleep(100000);
  }
}

- (void)m_capture: (NSString *)name
{
  [self normalizeAndDisplay];
  NSString *file = [outDir stringByAppendingPathComponent:
                                [name stringByAppendingPathExtension: @"png"]];
  NSString *cmd = [NSString stringWithFormat: @"import -window root %@", file];
  system([cmd UTF8String]);
  /* per-window crops: key window and any sheet-like panel */
  NSMutableString *info = [NSMutableString stringWithFormat: @"%@", name];
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible])
      {
        NSRect f = [w frame];
        [info appendFormat: @" FR=%@", NSStringFromClass([[w firstResponder] class])];
        NSView *gb = [[w contentView] viewWithTag: 0xEA0B0];
        if (gb) [info appendFormat: @" GROW=%@ in %@", NSStringFromRect([gb frame]), NSStringFromRect([[w contentView] bounds])];
        [info appendFormat: @" | %@ %@ %s%s dev=%p", NSStringFromClass([w class]),
              NSStringFromRect(f), [w isKeyWindow] ? "K" : "",
              "",
              [GSCurrentServer() windowDevice: [w windowNumber]]];
      }
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible] && [NSStringFromClass([w class]) hasSuffix: @"AlertPanel"])
      {
        NSView *cv = [w contentView];
        [info appendFormat: @"\n   ALERT cv=%@ super=%@", NSStringFromRect([cv frame]),
              NSStringFromRect([[cv superview] frame])];
        for (NSView *sv in [cv subviews])
          [info appendFormat: @"\n     %@ %@ mask=%lu", NSStringFromClass([sv class]),
                NSStringFromRect([sv frame]), (unsigned long)[sv autoresizingMask]];
      }
  [log_ addObject: info];
  fprintf(stderr, "AB CAP %s\n", [info UTF8String]);
  dumpMetrics(name);
}

- (void)m_saveWindow: (NSArray *)args
{
  /* args: name, predicate-class-substring; captures that window by X id */
  NSString *name = args[0];
  NSString *cls = args[1];
  [self normalizeAndDisplay];
  for (NSWindow *w in [NSApp windows])
    if ([w isVisible] && ([NSStringFromClass([w class]) rangeOfString: cls].location != NSNotFound
))
      {
        void *dev = [GSCurrentServer() windowDevice: [w windowNumber]];
        NSString *file = [outDir stringByAppendingPathComponent:
                                   [name stringByAppendingPathExtension: @"png"]];
        NSString *cmd = [NSString stringWithFormat: @"import -window %lu %@",
                                  (unsigned long)dev, file];
        system([cmd UTF8String]);
        fprintf(stderr, "AB WIN %s %s\n", [name UTF8String], [NSStringFromClass([w class]) UTF8String]);
        return;
      }
  fprintf(stderr, "AB WIN %s NOTFOUND\n", [name UTF8String]);
}

- (void)m_newClassic: (id)x { [_appDelegate performSelector: @selector(newDocument:) withObject: nil]; }
- (void)m_showShowcase: (id)x
{
  _showcase = [[EauShowcaseWindowController alloc] init];
  [_showcase showWindow];
}
- (void)m_selectSection: (NSNumber *)idx
{
  NSTableView *t = object_getIvar(_showcase, class_getInstanceVariable([_showcase class], "_sidebarTable"));
  [t selectRowIndexes: [NSIndexSet indexSetWithIndex: [idx integerValue]] byExtendingSelection: NO];
  [t scrollRowToVisible: [idx integerValue]];
}
- (void)m_perform: (NSString *)selName
{
  SEL sel = NSSelectorFromString(selName);
  IMP imp = [_showcase methodForSelector: sel];
  ((void (*)(id, SEL, id))imp)(_showcase, sel, nil);
}
- (void)m_alertPanel: (id)x
{
  NSRunAlertPanel(@"Run Alert Panel", @"NSRunAlertPanel informative text.", @"OK", @"Cancel", nil);
}
- (void)m_openPanel: (id)x
{
  NSOpenPanel *p = [NSOpenPanel openPanel];
  [p runModalForDirectory: @"/System/Library" file: nil types: nil];
}
- (void)m_savePanel: (id)x
{
  [[NSSavePanel savePanel] runModalForDirectory: @"/System/Library" file: @"Untitled"];
}
- (void)m_addHarnessMenu: (NSMenu *)main
{
  NSMenuItem *top = [[NSMenuItem alloc] initWithTitle: @"Harness" action: NULL keyEquivalent: @""];
  NSMenu *h = [[NSMenu alloc] initWithTitle: @"Harness"];
  [h addItemWithTitle: @"Plain Item" action: @selector(noop:) keyEquivalent: @"k"];
  NSMenuItem *dis = (NSMenuItem *)[h addItemWithTitle: @"Disabled Item" action: NULL keyEquivalent: @""];
  [dis setEnabled: NO];
  NSMenuItem *chk = (NSMenuItem *)[h addItemWithTitle: @"Checked Item" action: @selector(noop:) keyEquivalent: @"K"];
  [chk setState: NSOnState];
  [h addItem: [NSMenuItem separatorItem]];
  NSMenuItem *subItem = (NSMenuItem *)[h addItemWithTitle: @"Submenu" action: NULL keyEquivalent: @""];
  NSMenu *sub = [[NSMenu alloc] initWithTitle: @"Submenu"];
  [sub addItemWithTitle: @"Sub One" action: @selector(noop:) keyEquivalent: @""];
  [sub addItemWithTitle: @"Sub Two" action: @selector(noop:) keyEquivalent: @"2"];
  [h setSubmenu: sub forItem: subItem];
  NSMenuItem *longItem = (NSMenuItem *)[h addItemWithTitle: @"Long" action: NULL keyEquivalent: @""];
  NSMenu *lng = [[NSMenu alloc] initWithTitle: @"Long"];
  for (int i = 0; i < 90; i++)
    [lng addItemWithTitle: [NSString stringWithFormat: @"Long Item %02d", i]
                   action: @selector(noop:) keyEquivalent: @""];
  for (NSMenuItem *it in [lng itemArray]) [it setTarget: self];
  [h setSubmenu: lng forItem: longItem];
  for (NSMenuItem *it in [h itemArray]) if ([it action]) [it setTarget: self];
  for (NSMenuItem *it in [sub itemArray]) [it setTarget: self];
  [top setSubmenu: h];
  [main insertItem: top atIndex: [main numberOfItems] - 1];
}
- (void)noop: (id)s {}

/* Returns X root coords of the centre of main-menu item idx (or of item idx
 * in the given submenu's representation) */
- (void)m_itemPoint: (NSMutableArray *)io
{
  NSMenu *menu = io[0];
  NSInteger idx = [io[1] integerValue];
  NSMenuView *mv = (NSMenuView *)[menu menuRepresentation];
  NSWindow *w = [mv window];
  NSRect r = [mv rectOfItemAtIndex: idx];
  NSRect wr = [mv convertRect: r toView: nil];
  NSPoint p = [w convertBaseToScreen: NSMakePoint(NSMidX(wr), NSMidY(wr))];
  /* screen points -> X pixels */
  NSScreen *s = [w screen] ?: [NSScreen mainScreen];
  CGFloat k = 1.0; /* GNUstep frames are device pixels */
  NSRect sf = [s frame];
  int x = (int)lrint(p.x * k);
  int y = (int)lrint((NSMaxY(sf) - p.y) * k);
  fprintf(stderr, "AB ITEM %s[%ld] w=%p vis=%d pt=%d,%d k=%.2f\n", [[menu title] UTF8String],
          (long)idx, (__bridge void *)w, [w isVisible], x, y, k);
  [io addObject: @(x)];
  [io addObject: @(y)];
}

/* ---- driver thread ---- */
- (void)settle: (double)s { usleep((useconds_t)(s * 1e6)); }
- (void)cap: (NSString *)n { [self onMain: @selector(m_capture:) with: n]; }
/* Input goes through the abinput helper next to the app (see abinput.c):
 * a separate process keeps its X connection off GNUstep's, and xdotool's
 * XTest motion is a no-op on Xvfb. */
- (void)sh: (NSString *)c
{
  NSString *input = [[[NSBundle mainBundle] bundlePath]
    stringByAppendingPathComponent: @"../obj/abinput"];
  if ([c hasPrefix: @"xdotool "])
    c = [input stringByAppendingString: [c substringFromIndex: 7]];
  fprintf(stderr, "AB SH %s\n", [c UTF8String]);
  system([c UTF8String]);
}
- (void)clickMenu: (NSMenu *)m index: (NSInteger)i button: (BOOL)click
{
  NSMutableArray *io = [NSMutableArray arrayWithObjects: m, @(i), nil];
  [self onMain: @selector(m_itemPoint:) with: io];
  [self sh: [NSString stringWithFormat: @"xdotool mousemove %@ %@%@", io[2], io[3],
                      click ? @" click 1" : @""]];
}

- (void)run: (id)x
{
  @autoreleasepool {
  [self settle: 4.0];
  [self cap: @"01_classic"];
  [self sh: @"xdotool key Tab"];
  [self settle: 1.5];
  [self cap: @"02_classic_tab"];
  [self sh: @"xdotool key Tab"];
  [self settle: 1.5];
  [self cap: @"03_classic_tab2"];
  BOOL quick = getenv("AB_QUICK") != NULL;
  if (!quick) {
  /* menus */
  NSMenu *main = [NSApp mainMenu];
  [self cap: @"04_menubar"];
  NSInteger fileIdx = [main indexOfItemWithTitle: @"File"];
  NSInteger hIdx = [main indexOfItemWithTitle: @"Harness"];
  [self clickMenu: main index: fileIdx button: YES];
  [self settle: 1.5];
  [self cap: @"05_menu_file"];
  [self sh: @"xdotool mousemove 1500 1150 click 1"];
  [self settle: 1.5];
  [self clickMenu: main index: hIdx button: YES];
  [self settle: 1.5];
  NSMenu *h = [[main itemAtIndex: hIdx] submenu];
  [self clickMenu: h index: [h indexOfItemWithTitle: @"Submenu"] button: NO];
  [self settle: 3.5];
  [self cap: @"06_menu_submenu"];
  [self clickMenu: h index: [h indexOfItemWithTitle: @"Long"] button: NO];
  [self settle: 3.5];
  [self cap: @"07_menu_long"];
  {
    NSMenu *lng = [[h itemAtIndex: [h indexOfItemWithTitle: @"Long"]] submenu];
    [self clickMenu: lng index: 10 button: NO];
    [self settle: 1.0];
    [self sh: @"xdotool click 5 click 5 click 5"];
    [self settle: 3.5];
    [self cap: @"07b_menu_long_scrolled"];
  }
  [self sh: @"xdotool mousemove 1500 1150 click 1"];
  [self settle: 1.5];
  [self cap: @"08_after_menus"];

  }
  /* showcase */
  [self onMain: @selector(m_showShowcase:) with: nil];
  [self settle: 4.0];
  NSArray *sections = [EauShowcaseSectionRegistry allSections];
  for (NSUInteger i = 0; !quick && i < [sections count]; i++)
    {
      [self onMain: @selector(m_selectSection:) with: @(i)];
      [self settle: 3.5];
      [self cap: [NSString stringWithFormat: @"sc_%02lu_%@", (unsigned long)i,
                           [sections[i] identifier]]];
    }
  NSUInteger drawers = NSNotFound, alerts = NSNotFound;
  for (NSUInteger i = 0; i < [sections count]; i++)
    {
      if ([[sections[i] identifier] rangeOfString: @"rawer"].location != NSNotFound) drawers = i;
      if ([[sections[i] identifier] rangeOfString: @"lert"].location != NSNotFound) alerts = i;
    }
  if (drawers != NSNotFound && !quick)
    {
      [self onMain: @selector(m_selectSection:) with: @(drawers)];
      [self settle: 1.0];
      [self onMain: @selector(m_perform:) with: @"toggleDrawer:"];
      [self settle: 3.5];
      [self cap: @"20_drawer_open"];
      [self onMain: @selector(m_perform:) with: @"toggleDrawer:"];
      [self settle: 3.5];
    }
  if (alerts != NSNotFound)
    {
      [self onMain: @selector(m_selectSection:) with: @(alerts)];
      [self settle: 1.5];
      [self onMainAsync: @selector(m_perform:) with: @"showAlert:"];
      [self settle: 3.5];
      [self cap: @"21_alert"];
      [self onMain: @selector(m_saveWindow:) with: @[ @"21w_alert", @"Alert" ]];
      [self sh: @"xdotool key Return"];
      [self settle: 2.0];
      [self onMainAsync: @selector(m_perform:) with: @"showSheet:"];
      [self settle: 4.0];
      [self cap: @"22_sheet"];
      [self onMain: @selector(m_saveWindow:) with: @[ @"22w_sheet", @"Alert" ]];
      [self sh: @"xdotool key Return"];
      [self settle: 3.0];
      [self cap: @"23_after_sheet"];
      [self onMainAsync: @selector(m_perform:) with: @"showSaveSheet:"];
      [self settle: 4.0];
      [self cap: @"23b_save_sheet"];
      [self onMain: @selector(m_saveWindow:) with: @[ @"23bw_save_sheet", @"SavePanel" ]];
      [self sh: @"xdotool key Escape"];
      [self settle: 3.0];
    }
  [self onMainAsync: @selector(m_alertPanel:) with: nil];
  [self settle: 3.5];
  [self cap: @"24_runalertpanel"];
  [self onMain: @selector(m_saveWindow:) with: @[ @"24w_runalertpanel", @"Alert" ]];
  [self sh: @"xdotool key Return"];
  [self settle: 2.0];
  [self onMainAsync: @selector(m_openPanel:) with: nil];
  [self settle: 4.0];
  [self cap: @"25_openpanel"];
  [self onMain: @selector(m_saveWindow:) with: @[ @"25w_openpanel", @"OpenPanel" ]];
  [self sh: @"xdotool key Escape"];
  [self settle: 2.0];
  [self onMainAsync: @selector(m_savePanel:) with: nil];
  [self settle: 4.0];
  [self cap: @"26_savepanel"];
  [self onMain: @selector(m_saveWindow:) with: @[ @"26w_savepanel", @"SavePanel" ]];
  [self sh: @"xdotool key Escape"];
  [self settle: 2.0];
  [self cap: @"27_end"];
  [log_ writeToFile: [outDir stringByAppendingPathComponent: @"windows.plist"] atomically: YES];
  fprintf(stderr, "AB DONE\n");
  fflush(stderr);
  _exit(0);
  }
}
@end

static IMP origSetFrame, origSetFrameSize;
static BOOL interesting(NSView *v, CGFloat h)
{
  return [v isKindOfClass: [NSButton class]] && [[v window] isKindOfClass: NSClassFromString(@"EauAlertPanel")]
    && h > 20.01 && h < 21;
}
static void ab_setFrame(NSView *self, SEL _cmd, NSRect r)
{
  if (interesting(self, r.size.height))
    fprintf(stderr, "AB BTNFRAME setFrame %s\n%s\n", [NSStringFromRect(r) UTF8String],
            [[[NSThread callStackSymbols] description] UTF8String]);
  ((void (*)(id, SEL, NSRect))origSetFrame)(self, _cmd, r);
}
static void ab_setFrameSize(NSView *self, SEL _cmd, NSSize z)
{
  if (interesting(self, z.height))
    fprintf(stderr, "AB BTNFRAME setFrameSize %s\n%s\n", [NSStringFromSize(z) UTF8String],
            [[[NSThread callStackSymbols] description] UTF8String]);
  ((void (*)(id, SEL, NSSize))origSetFrameSize)(self, _cmd, z);
}
static IMP origSPTF;
static void ab_sptf(id self, SEL _cmd)
{
  fprintf(stderr, "AB SPTF begin frame=%s mask=%lu\n", [NSStringFromRect([self frame]) UTF8String],
          (unsigned long)[self styleMask]);
  for (NSView *sv in [[self contentView] subviews])
    fprintf(stderr, "AB SPTF   %s %s font=%s %.3f\n", [NSStringFromClass([sv class]) UTF8String],
            [NSStringFromRect([sv frame]) UTF8String],
            [sv respondsToSelector: @selector(font)] ? [[[(id)sv font] fontName] UTF8String] : "-",
            [sv respondsToSelector: @selector(font)] ? [[(id)sv font] pointSize] : 0.0);

  ((void (*)(id, SEL))origSPTF)(self, _cmd);
  fprintf(stderr, "AB SPTF end frame=%s cv=%s\n", [NSStringFromRect([self frame]) UTF8String], [NSStringFromRect([[self contentView] frame]) UTF8String]);
  for (NSView *sv in [[self contentView] subviews])
    fprintf(stderr, "AB SPTF  e %s %s\n", [NSStringFromClass([sv class]) UTF8String],
            [NSStringFromRect([sv frame]) UTF8String]);
}
@interface ABWatcher : NSObject
@end
@implementation ABWatcher
+ (void)resized: (NSNotification *)n
{
  NSWindow *w = [n object];
  if (![NSStringFromClass([w class]) hasSuffix: @"AlertPanel"] || getenv("AB_QUICK") == NULL)
    return;
  NSView *cv = [w contentView];
  NSMutableString *m = [NSMutableString stringWithFormat: @"AB RESIZE %@ frame=%@ cv=%@ ars=%d",
                                        [n name], NSStringFromRect([w frame]),
                                        NSStringFromRect([cv frame]), [cv autoresizesSubviews]];
  for (NSView *sv in [cv subviews])
    if ([sv isKindOfClass: [NSButton class]] || [sv isKindOfClass: [NSTextField class]])
      [m appendFormat: @" | %@", NSStringFromRect([sv frame])];
  fprintf(stderr, "%s\n", [m UTF8String]);
}
+ (void)willLaunch: (NSNotification *)n
{
  [driver m_addHarnessMenu: nil];
}
+ (void)launched: (NSNotification *)n
{
  if (getenv("AB_QUICK"))
    {
      Class c = NSClassFromString(@"EauAlertPanel");
      Method m = c ? class_getInstanceMethod(c, @selector(sizePanelToFit)) : NULL;
      if (m) origSPTF = method_setImplementation(m, (IMP)ab_sptf);
      origSetFrame = method_setImplementation(class_getInstanceMethod([NSView class], @selector(setFrame:)), (IMP)ab_setFrame);
      origSetFrameSize = method_setImplementation(class_getInstanceMethod([NSView class], @selector(setFrameSize:)), (IMP)ab_setFrameSize);
    }
  driver.appDelegate = [NSApp delegate];
  [NSThread detachNewThreadSelector: @selector(run:) toTarget: driver withObject: nil];
}
@end

static IMP origMenuBuilder;
static NSMenu *ab_mainMenu(id self, SEL _cmd, NSString *name)
{
  NSMenu *m = ((NSMenu *(*)(id, SEL, NSString *))origMenuBuilder)(self, _cmd, name);
  [driver m_addHarnessMenu: m];
  return m;
}

/* EauTest_main.m's main is compiled as eau_orig_main; this replicates it. */
int main(int argc, const char **argv)
{
  @autoreleasepool
    {
      outDir = [[[NSProcessInfo processInfo] environment] objectForKey: @"AB_OUT"];
      log_ = [NSMutableArray array];
      driver = [ABDriver new];
      [NSApplication sharedApplication];
      installDeterminism();
      [[NSNotificationCenter defaultCenter] addObserver: [ABWatcher class]
                                               selector: @selector(launched:)
                                                   name: NSApplicationDidFinishLaunchingNotification
                                                 object: nil];
      [[NSNotificationCenter defaultCenter] addObserver: [ABWatcher class]
                                               selector: @selector(resized:)
                                                   name: NSWindowDidResizeNotification
                                                 object: nil];
      [[NSNotificationCenter defaultCenter] addObserver: [ABWatcher class]
                                               selector: @selector(resized:)
                                                   name: NSWindowDidBecomeKeyNotification
                                                 object: nil];
      id delegate = [[NSClassFromString(@"EauTestAppDelegate") alloc] init];
      [NSApp setDelegate: delegate];
      {
        Method mb = class_getClassMethod(NSClassFromString(@"EauTestMenuBuilder"),
                                         @selector(mainMenuForApplicationName:));
        origMenuBuilder = method_setImplementation(mb, (IMP)ab_mainMenu);
      }
      [NSApp run];
    }
  return 0;
}
