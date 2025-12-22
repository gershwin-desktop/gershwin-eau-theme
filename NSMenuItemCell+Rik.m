// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Rik.h"
#import "NSMenuItemCell+Rik.h"
#import <objc/runtime.h>

@implementation Rik(NSMenuItemCell)
// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  RIKLOG(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  [xself RIKdrawKeyEquivalentWithFrame:cellFrame inView:controlView];
}
@end

@implementation NSMenuItemCell (RikTheme)

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

@end
