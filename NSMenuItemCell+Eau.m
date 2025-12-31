// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Eau.h"
#import "NSMenuItemCell+Eau.h"
#import <objc/runtime.h>

// Category on NSMenuItemCell used for method swizzling
@interface NSMenuItemCell (EauSwizzling)
- (CGFloat)eau_titleWidth;
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame;
@end

@implementation NSMenuItemCell (EauSwizzling)

// Swizzled implementation for titleWidth - adds padding
- (CGFloat)eau_titleWidth {
  EAULOG(@"NSMenuItemCell+Eau: eau_titleWidth called");

  // After swizzling, this message sends the original titleWidth implementation
  CGFloat originalWidth = [self eau_titleWidth];
  CGFloat paddedWidth = originalWidth + EAU_MENU_ITEM_PADDING;

  EAULOG(@"NSMenuItemCell+Eau: eau_titleWidth originalWidth=%f paddedWidth=%f", originalWidth, paddedWidth);

  return paddedWidth;
}

// Swizzled implementation for titleRectForBounds: - shifts title to center in padded space
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame {
  EAULOG(@"NSMenuItemCell+Eau: eau_titleRectForBounds: called with cellFrame=(%f, %f, %f, %f)",
        cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);

  // After swizzling, this message sends the original titleRectForBounds: implementation
  NSRect originalRect = [self eau_titleRectForBounds:cellFrame];

  // Shift by half padding to horizontally center in padded space
  originalRect.origin.x += (EAU_MENU_ITEM_PADDING / 2.0);

  EAULOG(@"NSMenuItemCell+Eau: eau_titleRectForBounds: returning rect=(%f, %f, %f, %f)",
        originalRect.origin.x, originalRect.origin.y, originalRect.size.width, originalRect.size.height);

  return originalRect;
}

@end

// This function runs when the bundle is loaded
__attribute__((constructor))
static void initMenuItemCellSwizzling(void) {
  // NSLog(@"NSMenuItemCell+Eau: Constructor called - setting up swizzling");

  Class menuItemCellClass = objc_getClass("NSMenuItemCell");
  if (!menuItemCellClass) {
    NSLog(@"NSMenuItemCell+Eau: ERROR - NSMenuItemCell class not found");
    return;
  }

  // Swizzle titleWidth - this is what NSMenuView uses to calculate item widths
  SEL titleWidthSelector = sel_registerName("titleWidth");
  Method originalTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, titleWidthSelector);
  Method swizzledTitleWidthMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_titleWidth));
  if (originalTitleWidthMethod && swizzledTitleWidthMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalTitleWidthMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTitleWidthMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTitleWidthMethod, swizzledTitleWidthMethod);
      // NSLog(@"NSMenuItemCell+Eau: Successfully swizzled titleWidth method");
    } else {
      // NSLog(@"NSMenuItemCell+Eau: titleWidth already swizzled, skipping");
    }
  } else {
    if (!originalTitleWidthMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original titleWidth method");
    }
    if (!swizzledTitleWidthMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_titleWidth method on NSMenuItemCell");
    }
  }

  // Swizzle titleRectForBounds: - this positions the title text
  SEL titleRectSelector = sel_registerName("titleRectForBounds:");
  Method originalTitleRectMethod = class_getInstanceMethod(menuItemCellClass, titleRectSelector);
  Method swizzledTitleRectMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_titleRectForBounds:));
  if (originalTitleRectMethod && swizzledTitleRectMethod) {
    // Avoid double-swizzling
    IMP originalIMP = method_getImplementation(originalTitleRectMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTitleRectMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTitleRectMethod, swizzledTitleRectMethod);
      // NSLog(@"NSMenuItemCell+Eau: Successfully swizzled titleRectForBounds: method");
    } else {
      // NSLog(@"NSMenuItemCell+Eau: titleRectForBounds: already swizzled, skipping");
    }
  } else {
    if (!originalTitleRectMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original titleRectForBounds: method");
    }
    if (!swizzledTitleRectMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_titleRectForBounds: method on NSMenuItemCell");
    }
  }
}

@implementation Eau(NSMenuItemCell)

// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  EAULOG(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
  NSMenuItemCell *xself = (NSMenuItemCell*)self;
  [xself EAUdrawKeyEquivalentWithFrame:cellFrame inView:controlView];
}

@end

@implementation NSMenuItemCell (EauTheme)

- (void) EAUdrawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView
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
      
      EAULOG(@"NSMenuItemCell+Eau: Drew submenu arrow at position: {%.1f, %.1f} size: {%.1f, %.1f}",
             position.x, position.y, size.width, size.height);
    } else {
      EAULOG(@"NSMenuItemCell+Eau: WARNING - No arrow image found for submenu item '%@'", [menuItem title]);
    }
    return; // Submenu items don't have key equivalents, so we're done
  }
  
  // For non-submenu items, handle key equivalents
  if (menuItem != nil) {
    NSString *originalKeyEquivalent = [menuItem keyEquivalent];
    NSUInteger modifierMask = [menuItem keyEquivalentModifierMask];
    
    EAULOG(@"NSMenuItemCell+Eau: Drawing key equivalent for '%@': '%@', modifiers: %lu", 
           [menuItem title], originalKeyEquivalent, (unsigned long)modifierMask);
    
    // Convert the key equivalent to Mac style if needed
    if (originalKeyEquivalent && [originalKeyEquivalent length] > 0) {
      NSString *macStyleKeyEquivalent = [self EAUconvertKeyEquivalentToMacStyle:originalKeyEquivalent withModifiers:modifierMask];
      
      if (![macStyleKeyEquivalent isEqualToString:originalKeyEquivalent]) {
        EAULOG(@"NSMenuItemCell+Eau: Drawing Mac style key equivalent '%@' instead of '%@'", macStyleKeyEquivalent, originalKeyEquivalent);
        
        // Draw the Mac-style key equivalent manually
        NSFont *font = [NSFont menuFontOfSize:0];
        NSColor *textColor = [NSColor controlTextColor];
        
        // If this menu item is highlighted, use highlighted text color
        if ([self isHighlighted]) {
          textColor = [NSColor selectedMenuItemTextColor];
        }
        // If this menu item is disabled, use disabled text color (greyed out)
        else if (![self isEnabled]) {
          textColor = [NSColor disabledControlTextColor];
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
        
        EAULOG(@"NSMenuItemCell+Eau: Drew Mac style key equivalent at rect: {{%.1f, %.1f}, {%.1f, %.1f}}", 
               textRect.origin.x, textRect.origin.y, textRect.size.width, textRect.size.height);
        return;
      }
    }
  }
  
  // If no conversion needed, do nothing - let the normal drawing process handle it
  EAULOG(@"NSMenuItemCell+Eau: No conversion needed, skipping custom drawing");
}

- (NSString*) EAUconvertKeyEquivalentToMacStyle: (NSString*)keyEquivalent withModifiers: (NSUInteger)modifierMask
{
  EAULOG(@"NSMenuItemCell+Eau: Converting key equivalent '%@' with modifiers %lu", keyEquivalent, (unsigned long)modifierMask);
  
  if (!keyEquivalent || [keyEquivalent length] == 0) {
    return keyEquivalent;
  }
  
  // Handle the old "#key" format first (this is what you're seeing)
  if ([keyEquivalent hasPrefix:@"#"] && [keyEquivalent length] > 1) {
    NSString *key = [keyEquivalent substringFromIndex:1];
    NSString *result = [NSString stringWithFormat:@"⌘%@", [key uppercaseString]];
    
    EAULOG(@"NSMenuItemCell+Eau: Converted old format '%@' to Mac style: '%@'", keyEquivalent, result);
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
    
    EAULOG(@"NSMenuItemCell+Eau: Converted to Mac style: '%@'", result);
    return result;
  }
  
  EAULOG(@"NSMenuItemCell+Eau: No conversion needed for '%@'", keyEquivalent);
  return keyEquivalent;
}

@end
