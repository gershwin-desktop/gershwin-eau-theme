#import "NSTableHeaderCell+Eau.h"
#import <objc/runtime.h>
#import <GNUstepGUI/GSTheme.h>

// Declare the custom theme methods
@interface GSTheme (EauTableExtensions)
- (NSFont *) tableHeaderFontOfSize: (CGFloat)fontSize;
- (NSTextAlignment) tableHeaderCellTextAlignment;
@end

@implementation NSTableHeaderCell (Eau)

+ (void) load
{
  // Exchange the initTextCell: method to set the small font by default
  Method originalInit = class_getInstanceMethod([NSTableHeaderCell class], @selector(initTextCell:));
  Method eauInit = class_getInstanceMethod([NSTableHeaderCell class], @selector(eau_initTextCell:));
  
  if (originalInit && eauInit)
    {
      method_exchangeImplementations(originalInit, eauInit);
    }
}

- (id) eau_initTextCell: (NSString *)aString
{
  // Call the original initialization (which is now the swizzled one)
  self = [self eau_initTextCell: aString];
  
  if (self)
    {
      // Override the font with the theme's table header font
      NSFont *headerFont = [[GSTheme theme] tableHeaderFontOfSize: 0];
      if (headerFont != nil)
        {
          [self setFont: headerFont];
        }
      
      // Keep left alignment as set in Eau+Table.m tableHeaderCellTextAlignment
      NSTextAlignment alignment = [[GSTheme theme] tableHeaderCellTextAlignment];
      [self setAlignment: alignment];
    }
  
  return self;
}

@end
