/* NSWindow+GBSheet.m - window side of window-modal sheets
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - -[NSWindow beginSheet:completionHandler:]
 * should not run a modal loop, -sheetParent should return the parent, and
 * NSWindow lacks -endSheet:, -endSheet:returnCode:, -beginCriticalSheet:
 * completionHandler: and -sheets.
 *
 * While a sheet is attached its parent keeps moving, resizing and redrawing,
 * but refuses clicks in its content, keyboard input (forwarded to the sheet),
 * closing and miniaturizing.  Other windows of the app are unaffected.
 */

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#include <stdlib.h>

#import "GBSheet.h"
#import "GBTheme.h"
#import "GBThemeHooks+Sheet.h"

@interface NSWindow (GBSheetPanelAPI)
- (BOOL)isActivePanel;
@end

@interface NSWindow (GBSheet)
- (void)gb_beginSheet:(NSWindow *)sheet
    completionHandler:(GSNSWindowDidEndSheetCallbackBlock)handler;
- (NSWindow *)gb_sheetParent;
- (void)gb_sendEvent:(NSEvent *)event;
- (void)gb_performClose:(id)sender;
- (void)gb_performMiniaturize:(id)sender;
- (void)gb_miniaturize:(id)sender;
@end

@interface GSWindowDecorationView (GBSheet)
- (void)gb_drawRect:(NSRect)rect;
@end

#pragma mark - Lazy per-class patches

static Class GBDefiningClass(Class cls, SEL sel)
{
  Class c;

  for (c = cls; c != Nil; c = class_getSuperclass(c)) {
    unsigned int count = 0;
    unsigned int i;
    BOOL found = NO;
    Method *list = class_copyMethodList(c, &count);

    for (i = 0; i < count && found == NO; i++) {
      found = sel_isEqual(method_getName(list[i]), sel);
    }
    free(list);
    if (found) {
      return c;
    }
  }
  return Nil;
}

/* Returns NO when (owner, sel) was already patched. */
static BOOL GBMarkPatched(Class owner, SEL sel)
{
  static NSMutableSet *patched = nil;
  NSString *key = [NSString stringWithFormat:@"%s %s", class_getName(owner), sel_getName(sel)];

  if (patched == nil) {
    patched = [NSMutableSet new];
  }
  if ([patched containsObject:key]) {
    return NO;
  }
  [patched addObject:key];
  return YES;
}

/* The runtime here has no imp_implementationWithBlock, so every patched
 * (class, selector) pair gets its own C trampoline from a small pool.  One
 * original per defining class keeps an override calling super working. */
#define GB_BOOL_SLOTS 16
#define GB_KEY_SLOTS 8

typedef BOOL (*GBBoolIMP)(id, SEL);
typedef BOOL (*GBKeyIMP)(id, SEL, NSEvent *);

static struct {
  GBBoolIMP orig;
  BOOL (*applies)(NSWindow *);
} sBoolSlots[GB_BOOL_SLOTS];
static unsigned int sBoolSlotCount = 0;

static GBKeyIMP sKeySlots[GB_KEY_SLOTS];
static unsigned int sKeySlotCount = 0;

#define GB_BOOL_TRAMPOLINE(n)                                                                      \
  static BOOL GBBoolTrampoline##n(id self, SEL _cmd)                                               \
  {                                                                                                \
    return sBoolSlots[n].applies(self) || sBoolSlots[n].orig(self, _cmd);                          \
  }
GB_BOOL_TRAMPOLINE(0)
GB_BOOL_TRAMPOLINE(1)
GB_BOOL_TRAMPOLINE(2)
GB_BOOL_TRAMPOLINE(3)
GB_BOOL_TRAMPOLINE(4)
GB_BOOL_TRAMPOLINE(5)
GB_BOOL_TRAMPOLINE(6)
GB_BOOL_TRAMPOLINE(7)
GB_BOOL_TRAMPOLINE(8)
GB_BOOL_TRAMPOLINE(9)
GB_BOOL_TRAMPOLINE(10)
GB_BOOL_TRAMPOLINE(11)
GB_BOOL_TRAMPOLINE(12)
GB_BOOL_TRAMPOLINE(13)
GB_BOOL_TRAMPOLINE(14)
GB_BOOL_TRAMPOLINE(15)

static const IMP sBoolTrampolines[GB_BOOL_SLOTS] = {
  (IMP)GBBoolTrampoline0,  (IMP)GBBoolTrampoline1,  (IMP)GBBoolTrampoline2,
  (IMP)GBBoolTrampoline3,  (IMP)GBBoolTrampoline4,  (IMP)GBBoolTrampoline5,
  (IMP)GBBoolTrampoline6,  (IMP)GBBoolTrampoline7,  (IMP)GBBoolTrampoline8,
  (IMP)GBBoolTrampoline9,  (IMP)GBBoolTrampoline10, (IMP)GBBoolTrampoline11,
  (IMP)GBBoolTrampoline12, (IMP)GBBoolTrampoline13, (IMP)GBBoolTrampoline14,
  (IMP)GBBoolTrampoline15
};

/* Panels that swallow key equivalents while "active" (alert panels) never
 * let Command-D reach their Don't Save button: offer them to the sheet
 * content first. */
#define GB_KEY_TRAMPOLINE(n)                                                                       \
  static BOOL GBKeyTrampoline##n(id self, SEL _cmd, NSEvent *event)                                \
  {                                                                                                \
    if (GBSheetIsActive(self) && ([event modifierFlags] & NSCommandKeyMask) &&                     \
        [[self contentView] performKeyEquivalent:event]) {                                         \
      return YES;                                                                                  \
    }                                                                                              \
    return sKeySlots[n](self, _cmd, event);                                                        \
  }
GB_KEY_TRAMPOLINE(0)
GB_KEY_TRAMPOLINE(1)
GB_KEY_TRAMPOLINE(2)
GB_KEY_TRAMPOLINE(3)
GB_KEY_TRAMPOLINE(4)
GB_KEY_TRAMPOLINE(5)
GB_KEY_TRAMPOLINE(6)
GB_KEY_TRAMPOLINE(7)

static const IMP sKeyTrampolines[GB_KEY_SLOTS] = { (IMP)GBKeyTrampoline0, (IMP)GBKeyTrampoline1,
                                                   (IMP)GBKeyTrampoline2, (IMP)GBKeyTrampoline3,
                                                   (IMP)GBKeyTrampoline4, (IMP)GBKeyTrampoline5,
                                                   (IMP)GBKeyTrampoline6, (IMP)GBKeyTrampoline7 };

/* Wraps the implementation cls actually uses for sel so an attached sheet
 * answers YES and everything else gets the original result. */
static void GBPatchBool(Class cls, SEL sel, BOOL (*applies)(NSWindow *))
{
  Class owner = GBDefiningClass(cls, sel);
  Method m;
  unsigned int n;

  if (owner == Nil || sBoolSlotCount >= GB_BOOL_SLOTS || GBMarkPatched(owner, sel) == NO) {
    return;
  }
  n = sBoolSlotCount++;
  m = class_getInstanceMethod(owner, sel);
  sBoolSlots[n].applies = applies;
  sBoolSlots[n].orig = (GBBoolIMP)method_setImplementation(m, sBoolTrampolines[n]);
}

static BOOL GBIsActiveSheet(NSWindow *w)
{
  return GBSheetIsActive(w);
}

static BOOL GBSheetIsModalException(NSWindow *w)
{
  return GBSheetWorksWhenModal(w);
}

void GBSheetPrepareClass(Class cls)
{
  SEL keyEquivalent = @selector(performKeyEquivalent:);
  Class owner;

  /* Sheets are borderless, which libs-gui refuses as key window. */
  GBPatchBool(cls, @selector(canBecomeKeyWindow), GBIsActiveSheet);
  GBPatchBool(cls, @selector(worksWhenModal), GBSheetIsModalException);
  /* libs-gui and Eau alert panels only react to their buttons while they
   * are "the active panel", which they equate with [NSApp modalWindow]. */
  if (class_getInstanceMethod(cls, @selector(isActivePanel)) != NULL) {
    GBPatchBool(cls, @selector(isActivePanel), GBIsActiveSheet);
  }

  /* NSWindow's own -performKeyEquivalent: already asks the content view;
   * only overrides (alert panels) need the trampoline. */
  owner = GBDefiningClass(cls, keyEquivalent);
  if (owner != Nil && owner != [NSWindow class] && sKeySlotCount < GB_KEY_SLOTS &&
      GBMarkPatched(owner, keyEquivalent)) {
    unsigned int n = sKeySlotCount++;
    Method m = class_getInstanceMethod(owner, keyEquivalent);

    sKeySlots[n] = (GBKeyIMP)method_setImplementation(m, sKeyTrampolines[n]);
  }
}

#pragma mark - Parent event filter

static BOOL GBPointInContent(NSWindow *window, NSEvent *event)
{
  NSView *content = [window contentView];

  return content != nil && NSPointInRect([event locationInWindow], [content frame]);
}

static void GBRefocusSheet(NSWindow *parent, NSWindow *sheet)
{
  [sheet orderWindow:NSWindowAbove relativeTo:[parent windowNumber]];
  if ([NSApp isActive] && [sheet isKeyWindow] == NO) {
    [sheet makeKeyWindow];
  }
}

/* YES when the event was consumed on behalf of the sheet. */
static BOOL GBFilterParentEvent(NSWindow *parent, NSWindow *sheet, NSEvent *event)
{
  switch ([event type]) {
    case NSLeftMouseDown:
    case NSRightMouseDown:
    case NSOtherMouseDown:
      /* The titlebar stays live so the parent (and its sheet) can be
       * dragged; its close and miniaturize buttons are refused below. */
      if (GBPointInContent(parent, event) == NO) {
        return NO;
      }
      if ([NSApp isActive] == NO) {
        [NSApp activateIgnoringOtherApps:YES];
      }
      [parent orderFront:nil];
      GBRefocusSheet(parent, sheet);
      return YES;

    case NSLeftMouseUp:
    case NSRightMouseUp:
    case NSOtherMouseUp:
    case NSLeftMouseDragged:
    case NSRightMouseDragged:
    case NSOtherMouseDragged:
    case NSScrollWheel:
      return GBPointInContent(parent, event);

    case NSKeyDown:
    case NSKeyUp:
    case NSFlagsChanged:
      /* The parent is only key for a moment (focus is handed to the sheet
       * right away); typing in that moment belongs to the sheet. */
      GBRefocusSheet(parent, sheet);
      [sheet sendEvent:event];
      return YES;

    case NSAppKitDefined:
      if ([event subtype] == GSAppKitWindowClose || [event subtype] == GSAppKitWindowMiniaturize) {
        NSBeep();
        return YES;
      }
      return NO;

    default:
      return NO;
  }
}

#pragma mark - NSWindow

static void GBWindowEndSheet(id self, SEL _cmd, NSWindow *sheet)
{
  if (GBSheetEnd(sheet, NSRunStoppedResponse) == NO) {
    [NSApp endSheet:sheet];
  }
}

static void GBWindowEndSheetReturnCode(id self, SEL _cmd, NSWindow *sheet, NSInteger code)
{
  if (GBSheetEnd(sheet, code) == NO) {
    [NSApp endSheet:sheet returnCode:code];
  }
}

static void GBWindowBeginCriticalSheet(id self, SEL _cmd, NSWindow *sheet,
                                       GSNSWindowDidEndSheetCallbackBlock handler)
{
  if (GBSheetsEnabled() && sheet != nil && sheet != self) {
    GBSheetBegin(sheet, self, nil, NULL, NULL, handler, YES);
    return;
  }
  [self beginSheet:sheet completionHandler:handler];
}

static NSArray *GBWindowSheets(id self, SEL _cmd)
{
  return GBSheetSheetsOf(self);
}

/* Adds Cocoa API libs-gui lacks, never replacing an existing version. */
static void GBAddMissing(Class cls, SEL sel, IMP imp, const char *types)
{
  if (class_getInstanceMethod(cls, sel) == NULL) {
    class_addMethod(cls, sel, imp, types);
  }
}

@implementation NSWindow (GBSheet)

+ (void)load
{
  Class cls = [NSWindow class];
  char types[64];

  GBSheetSwizzle(cls, @selector(beginSheet:completionHandler:),
                 @selector(gb_beginSheet:completionHandler:));
  GBSheetSwizzle(cls, @selector(sheetParent), @selector(gb_sheetParent));
  GBSheetSwizzle(cls, @selector(sendEvent:), @selector(gb_sendEvent:));
  GBSheetSwizzle(cls, @selector(performClose:), @selector(gb_performClose:));
  GBSheetSwizzle(cls, @selector(performMiniaturize:), @selector(gb_performMiniaturize:));
  GBSheetSwizzle(cls, @selector(miniaturize:), @selector(gb_miniaturize:));

  snprintf(types, sizeof(types), "v@:@");
  GBAddMissing(cls, @selector(endSheet:), (IMP)GBWindowEndSheet, types);
  snprintf(types, sizeof(types), "v@:@%s", @encode(NSInteger));
  GBAddMissing(cls, @selector(endSheet:returnCode:), (IMP)GBWindowEndSheetReturnCode, types);
  snprintf(types, sizeof(types), "v@:@@?");
  GBAddMissing(cls, @selector(beginCriticalSheet:completionHandler:),
               (IMP)GBWindowBeginCriticalSheet, types);
  GBAddMissing(cls, @selector(sheets), (IMP)GBWindowSheets, "@@:");

  GBSheetSwizzle([GSWindowDecorationView class], @selector(drawRect:), @selector(gb_drawRect:));
}

- (void)gb_beginSheet:(NSWindow *)sheet
    completionHandler:(GSNSWindowDidEndSheetCallbackBlock)handler
{
  if (GBSheetsEnabled() && sheet != nil && sheet != self) {
    GBSheetBegin(sheet, self, nil, NULL, NULL, handler, NO);
    return;
  }
  [self gb_beginSheet:sheet completionHandler:handler];
}

- (NSWindow *)gb_sheetParent
{
  NSWindow *parent = GBSheetParentOf(self);

  return (parent != nil) ? parent : [self gb_sheetParent];
}

- (void)gb_sendEvent:(NSEvent *)event
{
  NSWindow *sheet = GBSheetActiveSheetOf(self);

  if (sheet != nil && GBFilterParentEvent(self, sheet, event)) {
    return;
  }
  [self gb_sendEvent:event];

  /* Clicking the parent's titlebar or focusing it through the WM makes the
   * parent key; the sheet takes focus back so input keeps going to it. */
  if (sheet != nil && GBSheetActiveSheetOf(self) == sheet &&
      ([event type] == NSLeftMouseDown ||
       ([event type] == NSAppKitDefined && [event subtype] == GSAppKitWindowFocusIn))) {
    GBRefocusSheet(self, sheet);
  }
}

- (void)gb_performClose:(id)sender
{
  if (GBSheetActiveSheetOf(self) != nil) {
    NSBeep();
    return;
  }
  if (GBSheetDocumentWindowWillClose(self, sender)) {
    return;
  }
  [self gb_performClose:sender];
}

- (void)gb_performMiniaturize:(id)sender
{
  if (GBSheetActiveSheetOf(self) != nil) {
    NSBeep();
    return;
  }
  [self gb_performMiniaturize:sender];
}

- (void)gb_miniaturize:(id)sender
{
  if (GBSheetActiveSheetOf(self) != nil) {
    NSBeep();
    return;
  }
  [self gb_miniaturize:sender];
}

@end

#pragma mark - Sheet edge

@implementation GSWindowDecorationView (GBSheet)

/* The sheet is borderless, so nothing separates it from the parent content
 * below; the edge is drawn over the background, under the content. */
- (void)gb_drawRect:(NSRect)rect
{
  NSWindow *sheet;
  id theme;

  [self gb_drawRect:rect];

  sheet = [self window];
  if (GBSheetIsActive(sheet) == NO) {
    return;
  }
  theme = GBThemeIfResponds(@selector(drawSheetBorderInRect:forWindow:));
  if (theme != nil) {
    [theme drawSheetBorderInRect:[self bounds] forWindow:sheet];
  }
  else {
    [[NSColor darkGrayColor] set];
    NSFrameRect([self bounds]);
  }
}

@end
