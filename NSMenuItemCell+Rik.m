// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Rik.h"
#import "NSMenuItemCell+Rik.h"
#import <objc/runtime.h>

@implementation NSMenuItemCell (RikTheme)

// These methods will hold the original implementations after swizzling
- (CGFloat)RIK_originalTitleWidth {
  // After swizzling, this will contain the original implementation
  // Call original and add padding
  CGFloat originalWidth = [self RIK_originalTitleWidth];
  CGFloat paddedWidth = originalWidth + RIK_MENU_ITEM_PADDING;
  return paddedWidth;
}

- (NSRect)RIK_originalTitleRectForBounds:(NSRect)cellFrame {
  // After swizzling, this will call the original implementation
  NSRect originalRect = [self RIK_originalTitleRectForBounds:cellFrame];
  
  if ([self menuView]) {
    if ([[self menuView] isHorizontal]) {
      // Horizontal menu bar items - shift by half padding to center
      originalRect.origin.x += (RIK_MENU_ITEM_PADDING / 2.0);
    } else {
      // Vertical dropdown items - shift by half padding to center
      originalRect.origin.x += (RIK_MENU_ITEM_PADDING / 2.0);
    }
  }
  
  return originalRect;
}

// +load is called when the class is loaded, guaranteed to run after the class is ready
+ (void)load {
  RIKLOG(@"NSMenuItemCell+Rik: +load called - setting up swizzling");
  
  Class menuItemCellClass = [NSMenuItemCell class];
  if (!menuItemCellClass) {
    RIKLOG(@"NSMenuItemCell+Rik: ERROR - NSMenuItemCell class not found");
    return;
  }
  
  // Swizzle titleWidth - this is what NSMenuView uses to calculate item widths
  SEL originalTitleWidthSelector = @selector(titleWidth);
  SEL swizzledTitleWidthSelector = @selector(RIK_originalTitleWidth);
  
  Method originalTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, originalTitleWidthSelector);
  Method swizzledTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, swizzledTitleWidthSelector);
  
  if (originalTitleWidthMethod && swizzledTitleWidthMethod) {
    // Exchange implementations - this is thread-safe
    method_exchangeImplementations(originalTitleWidthMethod, swizzledTitleWidthMethod);
    RIKLOG(@"NSMenuItemCell+Rik: Successfully swizzled titleWidth method");
  } else {
    RIKLOG(@"NSMenuItemCell+Rik: ERROR - Could not find titleWidth method");
  }
  
  // Swizzle titleRectForBounds: - this positions the title text
  SEL originalTitleRectSelector = @selector(titleRectForBounds:);
  SEL swizzledTitleRectSelector = @selector(RIK_originalTitleRectForBounds:);
  
  Method originalTitleRectMethod = class_getInstanceMethod(menuItemCellClass, originalTitleRectSelector);
  Method swizzledTitleRectMethod = class_getInstanceMethod(menuItemCellClass, swizzledTitleRectSelector);
  
  if (originalTitleRectMethod && swizzledTitleRectMethod) {
    // Exchange implementations - this is thread-safe
    method_exchangeImplementations(originalTitleRectMethod, swizzledTitleRectMethod);
    RIKLOG(@"NSMenuItemCell+Rik: Successfully swizzled titleRectForBounds: method");
  } else {
    RIKLOG(@"NSMenuItemCell+Rik: ERROR - Could not find titleRectForBounds: method");
  }
}

- (void) RIKdrawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
{
  NSMenuItem *menuItem = [self menuItem];
  NSRect keyEquivRect = [self keyEquivalentRectForBounds: cellFrame];
  
  // First, draw the submenu arrow if this item has a submenu
  if ([menuItem hasSubmenu]) {
    NSImage *arrow = nil;
    
    if ([self isHighlighted]) {
      arrow = [NSImage imageNamed: @"NSHighlightedMenuArrow"];
    }
    if (arrow == nil) {
      arrow = [NSImage imageNamed: @"NSMenuArrow"];
    }
    // Fall back to common arrow images if NSMenuArrow is not found
    if (arrow == nil) {
      if ([self isHighlighted]) {
        arrow = [NSImage imageNamed: @"common_3DArrowRightH"];
      } else {
        arrow = [NSImage imageNamed: @"common_3DArrowRight"];
      }
    }
    
    if (arrow != nil) {
      NSSize size = [arrow size];
      NSPoint position;
      
      position.x = keyEquivRect.origin.x + keyEquivRect.size.width - size.width;
      position.y = MAX(NSMidY(keyEquivRect) - (size.height / 2.0), 0.0);
      
      // Adjust for flipped view
      if ([controlView isFlipped]) {
        position.y += size.height;
      }
      
      [arrow compositeToPoint: position operation: NSCompositeSourceOver];
      
      RIKLOG(@"NSMenuItemCell+Rik: Drew submenu arrow at position: {%.1f, %.1f} size: {%.1f, %.1f}",
             position.x, position.y, size.width, size.height);
    } else {
      RIKLOG(@"NSMenuItemCell+Rik: WARNING - No arrow image found for submenu item '%@'", [menuItem title]);
    }
    return; // Submenu items don't have key equivalents, so we're done
  }
  
  // For non-submenu items, handle key equivalents
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
        NSRect textRect = keyEquivRect;
        textRect.origin.x = NSMaxX(keyEquivRect) - textSize.width - 4; // 4 pixel margin from right
        textRect.origin.y = keyEquivRect.origin.y + (keyEquivRect.size.height - textSize.height) / 2;
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

@implementation Rik(NSMenuItemCell)

// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  RIKLOG(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  [xself RIKdrawKeyEquivalentWithFrame:cellFrame inView:controlView];
}

@end
