// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Rik.h"
#import "NSMenuItemCell+Rik.h"
#import <objc/runtime.h>

// Store original method implementations
static IMP originalTitleWidthIMP = NULL;
static IMP originalTitleRectForBoundsIMP = NULL;

// Our replacement titleWidth method - adds padding
static CGFloat swizzled_titleWidth(id self, SEL _cmd) {
  // Call original implementation
  CGFloat originalWidth = ((CGFloat (*)(id, SEL))originalTitleWidthIMP)(self, _cmd);
  
  // Add padding from Rik.h constant
  CGFloat paddedWidth = originalWidth + RIK_MENU_ITEM_PADDING;
  
  return paddedWidth;
}

// Our replacement titleRectForBounds: method - shifts title right by half the padding
static NSRect swizzled_titleRectForBounds(id self, SEL _cmd, NSRect cellFrame) {
  // Call original implementation
  NSRect originalRect = ((NSRect (*)(id, SEL, NSRect))originalTitleRectForBoundsIMP)(self, _cmd, cellFrame);
  
  // Shift the title rect right by half the padding to center text
  originalRect.origin.x += (RIK_MENU_ITEM_PADDING / 2.0);
  
  NSLog(@"NSMenuItemCell+Rik: swizzled_titleRectForBounds - shifted x by %.0f, new x: %.1f", 
         (RIK_MENU_ITEM_PADDING / 2.0), originalRect.origin.x);
  
  return originalRect;
}

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuItemCellSwizzling(void) {
  NSLog(@"NSMenuItemCell+Rik: Constructor called - setting up swizzling");
  
  Class menuItemCellClass = objc_getClass("NSMenuItemCell");
  if (!menuItemCellClass) {
    NSLog(@"NSMenuItemCell+Rik: ERROR - NSMenuItemCell class not found");
    return;
  }
  
  // Swizzle titleWidth - this is what NSMenuView uses to calculate item widths
  SEL titleWidthSelector = sel_registerName("titleWidth");
  Method titleWidthMethod = class_getInstanceMethod(menuItemCellClass, titleWidthSelector);
  if (titleWidthMethod) {
    originalTitleWidthIMP = method_getImplementation(titleWidthMethod);
    method_setImplementation(titleWidthMethod, (IMP)swizzled_titleWidth);
    NSLog(@"NSMenuItemCell+Rik: Successfully swizzled titleWidth method");
  } else {
    NSLog(@"NSMenuItemCell+Rik: ERROR - Could not find titleWidth method");
  }
  
  // Swizzle titleRectForBounds: - this positions the title text
  SEL titleRectSelector = sel_registerName("titleRectForBounds:");
  Method titleRectMethod = class_getInstanceMethod(menuItemCellClass, titleRectSelector);
  if (titleRectMethod) {
    originalTitleRectForBoundsIMP = method_getImplementation(titleRectMethod);
    method_setImplementation(titleRectMethod, (IMP)swizzled_titleRectForBounds);
    NSLog(@"NSMenuItemCell+Rik: Successfully swizzled titleRectForBounds: method");
  } else {
    NSLog(@"NSMenuItemCell+Rik: ERROR - Could not find titleRectForBounds: method");
  }
}

@implementation Rik(NSMenuItemCell)

// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  RIKLOG(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  [xself RIKdrawKeyEquivalentWithFrame:cellFrame inView:controlView];
}

// Override drawingRectForBounds to add padding
- (NSRect) _overrideNSMenuItemCellMethod_drawingRectForBounds: (NSRect)theRect {
  RIKLOG(@"_overrideNSMenuItemCellMethod_drawingRectForBounds:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  return [xself RIKdrawingRectForBounds:theRect];
}
@end

@implementation NSMenuItemCell (RikTheme)

- (CGFloat) RIKpreferredWidth
{
  RIKLOG(@"NSMenuItemCell+Rik: RIKpreferredWidth called");
  
  // Fallback to cellSize
  NSSize cellSize = [super cellSize];
  RIKLOG(@"NSMenuItemCell+Rik: RIKpreferredWidth - cellSize width: %.1f, padded: %.1f", 
         cellSize.width, cellSize.width + RIK_MENU_ITEM_PADDING);
  return cellSize.width + RIK_MENU_ITEM_PADDING;
}

- (void) RIKdrawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  NSMenuItem *menuItem = [self menuItem];
  
  if (menuItem != nil) {
    NSString *originalKeyEquivalent = [menuItem keyEquivalent];
    NSUInteger modifierMask = [menuItem keyEquivalentModifierMask];
    
    RIKLOG(@"NSMenuItemCell+Rik: Drawing key equivalent for '%@': '%@', modifiers: %lu", 
           [menuItem title], originalKeyEquivalent, (unsigned long)modifierMask);
    
    // Convert the key equivalent to Mac style if needed
    if (originalKeyEquivalent && [originalKeyEquivalent length] > 0) {
      NSString *macStyleKeyEquivalent = [self RIKconvertKeyEquivalentToMacStyle:originalKeyEquivalent withModifiers:modifierMask];
      
      if (![macStyleKeyEquivalent isEqualToString:originalKeyEquivalent]) {
        RIKLOG(@"NSMenuItemCell+Rik: Drawing Mac style key equivalent '%@' instead of '%@'", macStyleKeyEquivalent, originalKeyEquivalent);
        
        // Draw the Mac-style key equivalent manually
        NSFont *font = [NSFont menuFontOfSize:0];
        NSColor *textColor = [NSColor controlTextColor];
        
        // If this menu item is highlighted, use highlighted text color
        if ([self isHighlighted]) {
          textColor = [NSColor selectedMenuItemTextColor];
        }
        
        NSDictionary *attributes = @{
          NSFontAttributeName: font,
          NSForegroundColorAttributeName: textColor
        };
        
        // Calculate the size and position for right-aligned text
        NSSize textSize = [macStyleKeyEquivalent sizeWithAttributes:attributes];
        NSRect textRect = cellFrame;
        textRect.origin.x = NSMaxX(cellFrame) - textSize.width - 4; // 4 pixel margin from right
        textRect.origin.y = cellFrame.origin.y + (cellFrame.size.height - textSize.height) / 2;
        textRect.size = textSize;
        
        [macStyleKeyEquivalent drawInRect:textRect withAttributes:attributes];
        
        RIKLOG(@"NSMenuItemCell+Rik: Drew Mac style key equivalent at rect: {{%.1f, %.1f}, {%.1f, %.1f}}", 
               textRect.origin.x, textRect.origin.y, textRect.size.width, textRect.size.height);
        return;
      }
    }
  }
  
  // If no conversion needed, do nothing - let the normal drawing process handle it
  RIKLOG(@"NSMenuItemCell+Rik: No conversion needed, skipping custom drawing");
}

- (NSString*) RIKconvertKeyEquivalentToMacStyle: (NSString*)keyEquivalent withModifiers: (NSUInteger)modifierMask
{
  RIKLOG(@"NSMenuItemCell+Rik: Converting key equivalent '%@' with modifiers %lu", keyEquivalent, (unsigned long)modifierMask);
  
  if (!keyEquivalent || [keyEquivalent length] == 0) {
    return keyEquivalent;
  }
  
  // Handle the old "#key" format first (this is what you're seeing)
  if ([keyEquivalent hasPrefix:@"#"] && [keyEquivalent length] > 1) {
    NSString *key = [keyEquivalent substringFromIndex:1];
    NSString *result = [NSString stringWithFormat:@"⌘%@", [key uppercaseString]];
    
    RIKLOG(@"NSMenuItemCell+Rik: Converted old format '%@' to Mac style: '%@'", keyEquivalent, result);
    return result;
  }
  
  // Check if command modifier is present
  if (modifierMask & NSCommandKeyMask) {
    NSMutableString *result = [NSMutableString string];
    
    // Add modifier symbols in the correct order (following Mac conventions)
    if (modifierMask & NSControlKeyMask) {
      [result appendString:@"⌃"]; // Control symbol
    }
    if (modifierMask & NSAlternateKeyMask) {
      [result appendString:@"⌥"]; // Option/Alt symbol  
    }
    if (modifierMask & NSShiftKeyMask) {
      [result appendString:@"⇧"]; // Shift symbol
    }
    if (modifierMask & NSCommandKeyMask) {
      [result appendString:@"⌘"]; // Command symbol
    }
    
    // Convert key equivalent to uppercase if it's a letter
    NSString *keyToAdd = keyEquivalent;
    if ([keyEquivalent length] == 1) {
      unichar ch = [keyEquivalent characterAtIndex:0];
      if (ch >= 'a' && ch <= 'z') {
        keyToAdd = [keyEquivalent uppercaseString];
      }
    }
    
    [result appendString:keyToAdd];
    
    RIKLOG(@"NSMenuItemCell+Rik: Converted to Mac style: '%@'", result);
    return result;
  }
  
  RIKLOG(@"NSMenuItemCell+Rik: No conversion needed for '%@'", keyEquivalent);
  return keyEquivalent;
}

- (NSRect) RIKdrawingRectForBounds: (NSRect)theRect
{
  RIKLOG(@"NSMenuItemCell+Rik: RIKdrawingRectForBounds - original rect: {{%.1f, %.1f}, {%.1f, %.1f}}", 
         theRect.origin.x, theRect.origin.y, theRect.size.width, theRect.size.height);
  
  // No inset - just return the original rect
  return theRect;
}

@end
