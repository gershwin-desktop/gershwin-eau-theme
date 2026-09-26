/* NSDocument+GBSheet.m - the "save changes?" question as a document sheet
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 *
 * TODO: Upstream to GNUstep - -[NSDocument canCloseDocumentWithDelegate:
 * shouldCloseSelector:contextInfo:] should ask with an async sheet on
 * -windowForSheet, -[NSWindow performClose:] should use the async
 * -shouldCloseWindowController:delegate:..., and -[NSDocumentController
 * closeAllDocumentsWithDelegate:...] must not assume the callback is
 * synchronous.
 *
 * libs-gui asks with a blocking NSRunAlertPanel from -canCloseDocument and
 * the async variants just call it.  Here the async variants put up a sheet
 * on the document window and report from its answer; -canCloseDocument
 * (sync, used on quit) is left alone.
 */

#import <AppKit/AppKit.h>

#import "GBSheet.h"

@interface NSDocument (GBSheet)
- (void)gb_canCloseDocumentWithDelegate:(id)delegate
                    shouldCloseSelector:(SEL)shouldCloseSelector
                            contextInfo:(void *)contextInfo;
- (BOOL)gb_shouldCloseWindowController:(NSWindowController *)windowController;
@end

@interface NSDocumentController (GBSheet)
- (void)gb_closeAllDocumentsWithDelegate:(id)delegate
                     didCloseAllSelector:(SEL)didCloseAllSelector
                             contextInfo:(void *)contextInfo;
@end

@interface NSDocumentController (GBSheetPrivate)
- (void)_document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo;
@end

static NSArray *GBDocumentRunLoopModes(void)
{
  return [NSArray arrayWithObjects:NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                   NSEventTrackingRunLoopMode, nil];
}

static void GBCallShouldClose(id delegate, SEL selector, id sender, BOOL flag, void *contextInfo)
{
  void (*meth)(id, SEL, id, BOOL, void *);

  if (delegate == nil || selector == NULL) {
    return;
  }
  meth = (void (*)(id, SEL, id, BOOL, void *))[delegate methodForSelector:selector];
  if (meth != NULL) {
    meth(delegate, selector, sender, flag, contextInfo);
  }
}

/* Requests are referenced only by the alert/save callbacks, which do not
 * retain their delegates, so they keep themselves alive until answered. */
static NSMutableSet *sPending = nil;

static void GBKeepAlive(id request)
{
  if (sPending == nil) {
    sPending = [NSMutableSet new];
  }
  [sPending addObject:request];
}

#pragma mark - One document

@interface GBDocumentCloseRequest : NSObject {
  NSDocument *document;
  id delegate;
  SEL selector;
  void *contextInfo;
  BOOL answered;
}
- (id)initWithDocument:(NSDocument *)doc
              delegate:(id)aDelegate
              selector:(SEL)aSelector
           contextInfo:(void *)context;
- (void)askOnWindow:(NSWindow *)window;
@end

@implementation GBDocumentCloseRequest

- (id)initWithDocument:(NSDocument *)doc
              delegate:(id)aDelegate
              selector:(SEL)aSelector
           contextInfo:(void *)context
{
  if ((self = [super init]) != nil) {
    document = doc;
    delegate = aDelegate;
    selector = aSelector;
    contextInfo = context;
  }
  return self;
}

- (void)askOnWindow:(NSWindow *)window
{
  NSAlert *alert = [[NSAlert alloc] init];
  NSButton *dontSave;

  [alert setAlertStyle:NSWarningAlertStyle];
  [alert setMessageText:
             [NSString
                 stringWithFormat:@"Do you want to save the changes you made in the document “%@”?",
                                  [document displayName]]];
  [alert setInformativeText:@"Your changes will be lost if you don't save them."];
  [alert addButtonWithTitle:@"Save"];
  [[alert addButtonWithTitle:@"Cancel"] setKeyEquivalent:@"\e"];
  dontSave = [alert addButtonWithTitle:@"Don't Save"];
  [dontSave setKeyEquivalent:@"d"];
  [dontSave setKeyEquivalentModifierMask:NSCommandKeyMask];

  GBKeepAlive(self);
  [alert beginSheetModalForWindow:window
                    modalDelegate:self
                   didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
                      contextInfo:NULL];
}

- (void)answer:(BOOL)shouldClose
{
  if (answered) {
    return;
  }
  answered = YES;
  GBCallShouldClose(delegate, selector, document, shouldClose, contextInfo);
  [sPending removeObject:self];
}

- (void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)code contextInfo:(void *)unused
{
  switch (code) {
    case NSAlertFirstButtonReturn:
      [document saveDocumentWithDelegate:self
                         didSaveSelector:@selector(document:didSave:contextInfo:)
                             contextInfo:NULL];
      /* libs-gui never calls back when the save panel is cancelled; take
       * the document state once the save had its chance to report. */
      if (answered == NO) {
        [self performSelector:@selector(saveDidNotReport)
                   withObject:nil
                   afterDelay:0.0
                      inModes:GBDocumentRunLoopModes()];
      }
      break;

    case NSAlertThirdButtonReturn:
      [self answer:YES];
      break;

    default:
      [self answer:NO];
      break;
  }
}

- (void)document:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)unused
{
  [self answer:didSave];
}

- (void)saveDidNotReport
{
  [self answer:![document isDocumentEdited]];
}

@end

#pragma mark - Close all, one after another

@interface GBCloseAllRequest : NSObject {
  NSMutableArray *documents;
  id delegate;
  SEL selector;
  void *contextInfo;
  BOOL closeAll;
}
- (id)initWithDocuments:(NSArray *)docs
               delegate:(id)aDelegate
               selector:(SEL)aSelector
            contextInfo:(void *)context;
- (void)next;
@end

@implementation GBCloseAllRequest

- (id)initWithDocuments:(NSArray *)docs
               delegate:(id)aDelegate
               selector:(SEL)aSelector
            contextInfo:(void *)context
{
  if ((self = [super init]) != nil) {
    documents = [docs mutableCopy];
    delegate = aDelegate;
    selector = aSelector;
    contextInfo = context;
    closeAll = YES;
  }
  return self;
}

/* Same order and outcome as libs-gui (newest first, keep going after a
 * refusal), but each question waits for the previous answer. */
- (void)next
{
  NSDocument *doc = [documents lastObject];

  if (doc == nil) {
    GBCallShouldClose(delegate, selector, [NSDocumentController sharedDocumentController], closeAll,
                      contextInfo);
    [sPending removeObject:self];
    return;
  }
  [documents removeLastObject];
  [doc canCloseDocumentWithDelegate:self
                shouldCloseSelector:@selector(document:shouldClose:contextInfo:)
                        contextInfo:contextInfo];
}

- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)unused
{
  if (shouldClose) {
    [doc close];
  }
  else {
    closeAll = NO;
  }
  [self next];
}

@end

#pragma mark - Swizzles

static const void *kGBCloseApprovedKey = &kGBCloseApprovedKey;

@interface GBWindowCloseContinuation : NSObject {
  NSWindow *window;
  id sender;
}
- (id)initWithWindow:(NSWindow *)aWindow sender:(id)aSender;
@end

@implementation GBWindowCloseContinuation

- (id)initWithWindow:(NSWindow *)aWindow sender:(id)aSender
{
  if ((self = [super init]) != nil) {
    window = aWindow;
    sender = aSender;
  }
  return self;
}

- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)unused
{
  if (shouldClose) {
    /* Run the normal close path again (delegate checks, notifications);
     * the flag makes the synchronous document check agree without
     * asking a second time. */
    objc_setAssociatedObject(window, kGBCloseApprovedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [window performClose:sender];
    objc_setAssociatedObject(window, kGBCloseApprovedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
  [sPending removeObject:self];
}

@end

BOOL GBSheetDocumentWindowWillClose(NSWindow *window, id sender)
{
  NSWindowController *controller;
  NSDocument *document;
  GBWindowCloseContinuation *continuation;

  if (GBSheetsEnabled() == NO || objc_getAssociatedObject(window, kGBCloseApprovedKey) != nil) {
    return NO;
  }
  controller = [window windowController];
  document = [controller document];
  /* Same preconditions as libs-gui -performClose: before it would ask the
   * document; anything else takes the original path unchanged. */
  if (document == nil || [document isDocumentEdited] == NO ||
      ([window styleMask] & NSClosableWindowMask) == 0 ||
      ([NSApp modalWindow] != nil && [NSApp modalWindow] != window) ||
      [[document windowControllers] containsObject:controller] == NO ||
      ([controller shouldCloseDocument] == NO && [[document windowControllers] count] != 1)) {
    return NO;
  }

  continuation = [[GBWindowCloseContinuation alloc] initWithWindow:window sender:sender];
  GBKeepAlive(continuation);
  [document shouldCloseWindowController:controller
                               delegate:continuation
                    shouldCloseSelector:@selector(document:shouldClose:contextInfo:)
                            contextInfo:NULL];
  return YES;
}

@implementation NSDocument (GBSheet)

+ (void)load
{
  Class cls = [NSDocument class];

  GBSheetSwizzle(cls, @selector(canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:),
                 @selector(gb_canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:));
  GBSheetSwizzle(cls, @selector(shouldCloseWindowController:),
                 @selector(gb_shouldCloseWindowController:));
  GBSheetSwizzle([NSDocumentController class],
                 @selector(closeAllDocumentsWithDelegate:didCloseAllSelector:contextInfo:),
                 @selector(gb_closeAllDocumentsWithDelegate:didCloseAllSelector:contextInfo:));
}

- (void)gb_canCloseDocumentWithDelegate:(id)delegate
                    shouldCloseSelector:(SEL)shouldCloseSelector
                            contextInfo:(void *)contextInfo
{
  NSWindow *window = [self windowForSheet];
  GBDocumentCloseRequest *request;

  /* The libs-gui close-all loop reads its callback right after this call
   * returns, so it must keep getting a synchronous answer. */
  if (GBSheetsEnabled() == NO || [self isDocumentEdited] == NO || window == nil ||
      [window isVisible] == NO || GBSheetIsManaged(window) ||
      (sel_isEqual(shouldCloseSelector, @selector(_document:shouldClose:contextInfo:)) &&
       [delegate isKindOfClass:[NSDocumentController class]])) {
    [self gb_canCloseDocumentWithDelegate:delegate
                      shouldCloseSelector:shouldCloseSelector
                              contextInfo:contextInfo];
    return;
  }

  request = [[GBDocumentCloseRequest alloc] initWithDocument:self
                                                    delegate:delegate
                                                    selector:shouldCloseSelector
                                                 contextInfo:contextInfo];
  [request askOnWindow:window];
}

- (BOOL)gb_shouldCloseWindowController:(NSWindowController *)windowController
{
  if (objc_getAssociatedObject([windowController window], kGBCloseApprovedKey) != nil) {
    return YES;
  }
  return [self gb_shouldCloseWindowController:windowController];
}

@end

@implementation NSDocumentController (GBSheet)

/* The original body assumes -canCloseDocumentWithDelegate: answers before
 * returning; with sheets it would close every document unasked, so it only
 * runs when sheets are off. */
- (void)gb_closeAllDocumentsWithDelegate:(id)delegate
                     didCloseAllSelector:(SEL)didCloseAllSelector
                             contextInfo:(void *)contextInfo
{
  GBCloseAllRequest *request;

  if (GBSheetsEnabled() == NO) {
    [self gb_closeAllDocumentsWithDelegate:delegate
                       didCloseAllSelector:didCloseAllSelector
                               contextInfo:contextInfo];
    return;
  }
  request = [[GBCloseAllRequest alloc] initWithDocuments:[self documents]
                                                delegate:delegate
                                                selector:didCloseAllSelector
                                             contextInfo:contextInfo];
  GBKeepAlive(request);
  [request next];
}

@end
