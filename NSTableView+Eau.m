#import "NSTableView+Eau.h"
#import <objc/runtime.h>
#import <GNUstepGUI/GSTheme.h>

// Declare the custom theme method
@interface GSTheme (EauTableExtensions)
- (CGFloat) tableHeaderRowHeight;
@end

@interface NSTableView (EauInit)
- (id)eau_initWithFrame: (NSRect)frameRect __attribute__((objc_method_family(init)));
@end

@implementation NSTableView (Eau)

+ (void) load
{
  // Exchange the initWithFrame: method to enable alternating row colors by default
  Method originalInit = class_getInstanceMethod([NSTableView class], @selector(initWithFrame:));
  Method eauInit = class_getInstanceMethod([NSTableView class], @selector(eau_initWithFrame:));
  
  if (originalInit && eauInit)
    {
      method_exchangeImplementations(originalInit, eauInit);
    }
}

- (id) eau_initWithFrame: (NSRect)frameRect
{
  // Call the original initialization
  self = [self eau_initWithFrame: frameRect];
  
  if (self)
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
