#import "NSTableView+Eau.h"
#import "Eau.h"
#import <objc/runtime.h>
#import <GNUstepGUI/GSTheme.h>

// Declare the custom theme method
@interface GSTheme (EauTableExtensions)
- (CGFloat) tableHeaderRowHeight;
@end

@interface NSTableView (EauInit)
- (id)eau_initWithFrame: (NSRect)frameRect __attribute__((objc_method_family(init)));
@end

/* A selection is grey unless the table takes the keys in the key window
 * (Eau+Table.m), so it has to be redrawn whenever either changes. */
@interface EauTableSelectionRedrawer : NSObject
@end

@implementation EauTableSelectionRedrawer

+ (void) redrawSelectionsInView: (NSView *)view
{
  NSEnumerator *e;
  NSView *subview;

  if ([view isKindOfClass: [NSTableView class]]
      && [(NSTableView *)view numberOfSelectedRows] > 0)
    {
      [view setNeedsDisplay: YES];
    }
  e = [[view subviews] objectEnumerator];
  while ((subview = [e nextObject]) != nil)
    {
      [self redrawSelectionsInView: subview];
    }
}

+ (void) windowKeyStateChanged: (NSNotification *)notification
{
  if (EauThemeIsActive())
    {
      [self redrawSelectionsInView: [[notification object] contentView]];
    }
}

@end

/* NSTableView inherits the first responder methods, so they are added to
 * it rather than exchanged: exchanging an inherited method would change it
 * for every responder.  The added version calls the inherited one. */
static BOOL EauTableFirstResponderChanged(id self, SEL _cmd)
{
  IMP inherited = class_getMethodImplementation([NSControl class], _cmd);
  BOOL accepted = ((BOOL (*)(id, SEL))inherited)(self, _cmd);

  if (accepted && [(NSTableView *)self numberOfSelectedRows] > 0)
    {
      [(NSTableView *)self setNeedsDisplay: YES];
    }
  return accepted;
}

static void EauAddFirstResponderHook(SEL sel)
{
  Method inherited = class_getInstanceMethod([NSControl class], sel);

  if (class_addMethod([NSTableView class], sel,
                      (IMP)EauTableFirstResponderChanged,
                      method_getTypeEncoding(inherited)) == NO)
    {
      NSLog(@"Eau: NSTableView implements %@ itself; selections will not "
            @"turn grey when it loses the keyboard", NSStringFromSelector(sel));
    }
}

static void EauExchange(SEL original, SEL replacement)
{
  Method a = class_getInstanceMethod([NSTableView class], original);
  Method b = class_getInstanceMethod([NSTableView class], replacement);

  if (a && b)
    {
      method_exchangeImplementations(a, b);
    }
}

@implementation NSTableView (Eau)

+ (void) load
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  // Exchange the initWithFrame: method to enable alternating row colors by default
  EauExchange(@selector(initWithFrame:), @selector(eau_initWithFrame:));
  EauAddFirstResponderHook(@selector(becomeFirstResponder));
  EauAddFirstResponderHook(@selector(resignFirstResponder));

  [nc addObserver: [EauTableSelectionRedrawer class]
         selector: @selector(windowKeyStateChanged:)
             name: NSWindowDidBecomeKeyNotification
           object: nil];
  [nc addObserver: [EauTableSelectionRedrawer class]
         selector: @selector(windowKeyStateChanged:)
             name: NSWindowDidResignKeyNotification
           object: nil];
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  // Call the original initialization
  self = [self eau_initWithFrame: frameRect];
  
  if (self && EauThemeIsActive())
    {
      // Enable alternating row background colors by default in Eau theme
      [self setUsesAlternatingRowBackgroundColors: YES];
      
      // Set row height to match menu item height (22px) from AppearanceMetrics
      [self setRowHeight: 22.0];
      
      // Disable all grid lines - we'll draw only horizontal lines via the theme
      [self setGridStyleMask: 0];
      
      // Set grid color to transparent to ensure no lines show
      [self setGridColor: [NSColor clearColor]];
      
      // Set header view height to use the custom theme height
      NSTableHeaderView *headerView = [self headerView];
      if (headerView != nil)
        {
          CGFloat headerHeight = [[GSTheme theme] tableHeaderRowHeight];
          NSSize headerSize = [headerView frame].size;
          headerSize.height = headerHeight;
          [headerView setFrameSize: headerSize];
        }
    }
  
  return self;
}

@end
