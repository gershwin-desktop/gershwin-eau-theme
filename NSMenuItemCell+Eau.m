// The purpose of this code is to draw command key equivalents in the menu using the Command key symbol

#import "Eau.h"
#import "NSMenuItemCell+Eau.h"
#import <objc/runtime.h>

// Category on NSMenuItemCell used for method swizzling
@interface NSMenuItemCell (EauSwizzling)
- (CGFloat)eau_titleWidth;
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame;
- (NSColor *)eau_textColor;
- (void)eau_drawImageWithFrame:(NSRect)cellFrame inView:(NSView*)controlView;
- (CGFloat)eau_imageWidth;
- (NSRect)eau_imageRectForBounds:(NSRect)cellFrame;
- (CGFloat)eau_keyEquivalentWidth;
@end

/* Centering an image in a cell whose frame is fractional (menu bar items are
   as wide as their text) leaves its origin between device pixels, and the
   backend then resamples the bitmap, smearing it.  Snap the origin to the
   pixel grid but keep the size so the image is never rescaled. */
/* libs-gui insets a horizontal menu cell by two points at its bottom edge, to
   clear a menu border that a horizontal menu does not draw.  Centering an icon
   in that inset rect leaves it one point above the middle of the menu bar, so
   the icon is centered on the whole bar instead.  The inset stays for the
   title, where it lifts the text off the descender and looks right. */
static CGFloat EauImageCenterY(NSRect drawnRect, NSMenuItemCell *cell, NSView *controlView)
{
  if ([[cell menuView] isHorizontal])
    return NSMidY([controlView bounds]);
  return NSMidY(drawnRect);
}

static NSRect EauPixelAlignedImageRect(NSView *view, NSPoint origin, NSSize size)
{
  NSRect rect = [view centerScanRect: NSMakeRect(origin.x, origin.y,
                                                 size.width, size.height)];
  rect.size = size;
  return rect;
}

@implementation NSMenuItemCell (EauSwizzling)

// Swizzled implementation for titleWidth - adds padding
- (CGFloat)eau_titleWidth {
  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleWidth called");

  // After swizzling, this message sends the original titleWidth implementation
  CGFloat originalWidth = [self eau_titleWidth];
  CGFloat paddedWidth;

  if (!EauThemeIsActive())
    return originalWidth;

  paddedWidth = originalWidth + EAU_MENU_ITEM_PADDING;

  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleWidth originalWidth=%f paddedWidth=%f", originalWidth, paddedWidth);

  return paddedWidth;
}

// Swizzled implementation for titleRectForBounds: - shifts title to center in
// padded space and corrects the title offset for a capped icon width.
- (NSRect)eau_titleRectForBounds:(NSRect)cellFrame {
  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleRectForBounds: called with cellFrame=(%f, %f, %f, %f)",
        cellFrame.origin.x, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);

  // After swizzling, this message sends the original titleRectForBounds: implementation
  NSRect originalRect = [self eau_titleRectForBounds:cellFrame];

  if (!EauThemeIsActive())
    return originalRect;

  // GNUstep's original offsets the title by the RAW image width (_imageWidth),
  // which is the full icon size (e.g. 128px).  The image column is capped to
  // the theme's icon size, so pull the title back left by the difference,
  // otherwise text lands far to the right of a small icon.
  NSMenuItem *item = [self menuItem];
  NSImage *image = [item image];
  NSString *title = [item title];
  if (image && title && [title length] > 0)
    {
      NSSize imgSize = [image size];
      CGFloat rawWidth = imgSize.width;
      CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
      CGFloat cappedWidth = MIN(rawWidth, iconSize);
      if (rawWidth > cappedWidth)
        {
          CGFloat delta = rawWidth - cappedWidth;
          originalRect.origin.x -= delta;
          originalRect.size.width += delta;
        }
    }

  // Shift by half padding to horizontally center in padded space
  originalRect.origin.x += (EAU_MENU_ITEM_PADDING / 2.0);

  NSDebugLog(@"NSMenuItemCell+Eau: eau_titleRectForBounds: returning rect=(%f, %f, %f, %f)",
        originalRect.origin.x, originalRect.origin.y, originalRect.size.width, originalRect.size.height);

  return originalRect;
}

// Swizzled implementation for textColor - returns lighter grey for disabled menu items
- (NSColor *)eau_textColor {
  if (EauThemeIsActive() && ![self isEnabled]) {
    return [NSColor colorWithCalibratedWhite: 0.65 alpha: 1.0];
  }
  return [self eau_textColor];
}

// Swizzled implementation for drawImageWithFrame:inView: —
// when image IS the title (image + empty title), draw centered in full cell;
// when the item has both an icon and a title, scale the icon down to the
// theme's menuItemIconSize so a large app/prefPane icon renders small.
- (void)eau_drawImageWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
  NSMenuItem *item = [self menuItem];
  NSImage *image = [item image];
  NSString *title = [item title];
  if (image && EauThemeIsActive())
    {
      NSSize imgSize = [image size];
      if (!title || [title length] == 0)
        {
          /* Image is the whole item - draw centered in the full cell. */
          CGFloat scale = MIN(cellFrame.size.width / imgSize.width,
                              cellFrame.size.height / imgSize.height);
          if (scale > 1.0) scale = 1.0;
          NSSize drawSize = NSMakeSize(imgSize.width * scale,
                                       imgSize.height * scale);
          NSPoint drawPoint = NSMakePoint(NSMidX(cellFrame) - drawSize.width / 2,
                                          EauImageCenterY(cellFrame, self, controlView)
                                            - drawSize.height / 2);
          [image drawInRect: EauPixelAlignedImageRect(controlView, drawPoint, drawSize)
                   fromRect: NSZeroRect
                  operation: NSCompositeSourceOver
                   fraction: 1.0];
          return;
        }
      else
        {
          /* Icon next to a title: draw in the (capped) image column rect,
             scaled down (never up) to fit the theme's icon size. */
          NSRect imageRect = [self imageRectForBounds: cellFrame];
          CGFloat iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
          if (imageRect.size.width > iconSize)
            imageRect.size.width = iconSize;
          CGFloat scale = MIN(imageRect.size.width / imgSize.width,
                              imageRect.size.height / imgSize.height);
          if (scale > 1.0) scale = 1.0;
          NSSize drawSize = NSMakeSize(imgSize.width * scale,
                                       imgSize.height * scale);
          NSPoint drawPoint = NSMakePoint(NSMidX(imageRect) - drawSize.width / 2,
                                          EauImageCenterY(imageRect, self, controlView)
                                            - drawSize.height / 2);
          [image drawInRect: EauPixelAlignedImageRect(controlView, drawPoint, drawSize)
                   fromRect: NSZeroRect
                  operation: NSCompositeSourceOver
                   fraction: 1.0];
          return;
        }
    }
  [self eau_drawImageWithFrame: cellFrame inView: controlView];
}

/* GNUstep sizes the key equivalent column from its own rendering, which drops
   function keys entirely and spells modifiers differently from the symbols we
   draw.  Reserve room for what is actually drawn, never less than before.
   TODO: Upstream to GNUstep - NSMenuItemCell should measure and draw function-key
   and modifier-less key equivalents instead of dropping them. */
- (CGFloat)eau_keyEquivalentWidth
{
  CGFloat width = [self eau_keyEquivalentWidth];
  NSMenuItem *menuItem = [self menuItem];

  if (EauThemeIsActive() && menuItem != nil && ![menuItem hasSubmenu])
    {
      NSString *display = [self EAUconvertKeyEquivalentToMacStyle: [menuItem keyEquivalent]
                                                    withModifiers: [menuItem keyEquivalentModifierMask]];
      if ([display length] > 0)
        {
          NSDictionary *attributes = @{ NSFontAttributeName: [NSFont menuFontOfSize: 0] };
          CGFloat drawnWidth = [display sizeWithAttributes: attributes].width + 8.0;
          width = MAX(width, drawnWidth);
        }
    }

  return width;
}

/* Cap the image column width so a large app/prefPane icon does not widen the
   whole menu.  NSMenuView lays out the menu using imageWidth, so it must be
   capped too - not just the drawn image. */
- (CGFloat)eau_imageWidth
{
  CGFloat width = [self eau_imageWidth];
  CGFloat iconSize;

  if (!EauThemeIsActive())
    return width;

  iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
  if (width > iconSize)
    return iconSize;
  return width;
}

/* Cap the image rect width to the same icon size.  The default rect is as
   wide as the image itself; drawing into a capped rect keeps the icon small
   and aligned in the image column. */
- (NSRect)eau_imageRectForBounds:(NSRect)cellFrame
{
  NSRect rect = [self eau_imageRectForBounds: cellFrame];
  CGFloat iconSize;

  if (!EauThemeIsActive())
    return rect;

  iconSize = [(Eau *)[GSTheme theme] menuItemIconSize];
  if (rect.size.width > iconSize)
    rect.size.width = iconSize;
  return rect;
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

  // Swizzle textColor - returns lighter grey for disabled items
  SEL textColorSelector = sel_registerName("textColor");
  Method originalTextColorMethod = class_getInstanceMethod(menuItemCellClass, textColorSelector);
  Method swizzledTextColorMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_textColor));
  if (originalTextColorMethod && swizzledTextColorMethod) {
    IMP originalIMP = method_getImplementation(originalTextColorMethod);
    IMP swizzledIMP = method_getImplementation(swizzledTextColorMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalTextColorMethod, swizzledTextColorMethod);
    }
  } else {
    if (!originalTextColorMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original textColor method");
    }
    if (!swizzledTextColorMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_textColor method on NSMenuItemCell");
    }
  }

  // Swizzle drawImageWithFrame:inView: — draws image centered in full cell
  // when the image IS the menu title (image + empty title)
  SEL drawImageSelector = sel_registerName("drawImageWithFrame:inView:");
  Method originalDrawImageMethod = class_getInstanceMethod(menuItemCellClass, drawImageSelector);
  Method swizzledDrawImageMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_drawImageWithFrame:inView:));
  if (originalDrawImageMethod && swizzledDrawImageMethod) {
    IMP originalIMP = method_getImplementation(originalDrawImageMethod);
    IMP swizzledIMP = method_getImplementation(swizzledDrawImageMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalDrawImageMethod, swizzledDrawImageMethod);
    }
  } else {
    if (!originalDrawImageMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find original drawImageWithFrame:inView: method");
    }
    if (!swizzledDrawImageMethod) {
      NSLog(@"NSMenuItemCell+Eau: ERROR - Could not find eau_drawImageWithFrame:inView: method on NSMenuItemCell");
    }
  }

  // Swizzle imageWidth - caps the image column so large icons stay small
  SEL imageWidthSelector = sel_registerName("imageWidth");
  Method originalImageWidthMethod = class_getInstanceMethod(menuItemCellClass, imageWidthSelector);
  Method swizzledImageWidthMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_imageWidth));
  if (originalImageWidthMethod && swizzledImageWidthMethod) {
    IMP originalIMP = method_getImplementation(originalImageWidthMethod);
    IMP swizzledIMP = method_getImplementation(swizzledImageWidthMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalImageWidthMethod, swizzledImageWidthMethod);
    }
  } else {
    NSLog(@"NSMenuItemCell+Eau: WARNING - Could not swizzle imageWidth (orig=%p swiz=%p)",
      originalImageWidthMethod, swizzledImageWidthMethod);
  }

  // Swizzle keyEquivalentWidth - reserves room for the symbols we draw
  SEL keyEquivalentWidthSelector = sel_registerName("keyEquivalentWidth");
  Method originalKeyEquivalentWidthMethod = class_getInstanceMethod(menuItemCellClass, keyEquivalentWidthSelector);
  Method swizzledKeyEquivalentWidthMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_keyEquivalentWidth));
  if (originalKeyEquivalentWidthMethod && swizzledKeyEquivalentWidthMethod) {
    IMP originalIMP = method_getImplementation(originalKeyEquivalentWidthMethod);
    IMP swizzledIMP = method_getImplementation(swizzledKeyEquivalentWidthMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalKeyEquivalentWidthMethod, swizzledKeyEquivalentWidthMethod);
    }
  } else {
    NSLog(@"NSMenuItemCell+Eau: WARNING - Could not swizzle keyEquivalentWidth (orig=%p swiz=%p)",
      originalKeyEquivalentWidthMethod, swizzledKeyEquivalentWidthMethod);
  }

  // Swizzle imageRectForBounds: - caps the image draw rect to icon size
  SEL imageRectSelector = sel_registerName("imageRectForBounds:");
  Method originalImageRectMethod = class_getInstanceMethod(menuItemCellClass, imageRectSelector);
  Method swizzledImageRectMethod = class_getInstanceMethod(menuItemCellClass, @selector(eau_imageRectForBounds:));
  if (originalImageRectMethod && swizzledImageRectMethod) {
    IMP originalIMP = method_getImplementation(originalImageRectMethod);
    IMP swizzledIMP = method_getImplementation(swizzledImageRectMethod);
    if (originalIMP != swizzledIMP) {
      method_exchangeImplementations(originalImageRectMethod, swizzledImageRectMethod);
    }
  } else {
    NSLog(@"NSMenuItemCell+Eau: WARNING - Could not swizzle imageRectForBounds: (orig=%p swiz=%p)",
      originalImageRectMethod, swizzledImageRectMethod);
  }
}

@implementation Eau(NSMenuItemCell)

// Override drawKeyEquivalentWithFrame to intercept just the key equivalent drawing
- (void) _overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame: (NSRect)cellFrame inView: (NSView*)controlView {
  NSDebugLog(@"_overrideNSMenuItemCellMethod_drawKeyEquivalentWithFrame:inView:");
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
      
      NSDebugLog(@"NSMenuItemCell+Eau: Drew submenu arrow at position: {%.1f, %.1f} size: {%.1f, %.1f}",
             position.x, position.y, size.width, size.height);
    } else {
      NSDebugLog(@"NSMenuItemCell+Eau: WARNING - No arrow image found for submenu item '%@'", [menuItem title]);
    }
    return; // Submenu items don't have key equivalents, so we're done
  }
  
  // For non-submenu items, handle key equivalents
  if (menuItem != nil) {
    NSString *display = [self EAUconvertKeyEquivalentToMacStyle: [menuItem keyEquivalent]
                                                 withModifiers: [menuItem keyEquivalentModifierMask]];

    /* This method replaces NSMenuItemCell's own drawKeyEquivalentWithFrame:,
       so whatever is not drawn here is not drawn at all - including the
       function keys and modifier-less equivalents GNUstep itself refuses to
       render. */
    if ([display length] > 0) {
      NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont menuFontOfSize: 0],
        NSForegroundColorAttributeName: [self textColor]
      };

      NSSize textSize = [display sizeWithAttributes: attributes];
      NSRect textRect = keyEquivRect;
      textRect.origin.x = NSMaxX(keyEquivRect) - textSize.width - 4; // 4 pixel margin from right
      textRect.origin.y = keyEquivRect.origin.y + (keyEquivRect.size.height - textSize.height) / 2;
      textRect.size = textSize;

      [display drawInRect: textRect withAttributes: attributes];

      NSDebugLog(@"NSMenuItemCell+Eau: Drew key equivalent '%@' at rect: {{%.1f, %.1f}, {%.1f, %.1f}}",
             display, textRect.origin.x, textRect.origin.y, textRect.size.width, textRect.size.height);
    }
  }
}

/* The symbol a key equivalent is shown with.  Foreign menus arrive as X11
   keysym names ("Up", "Page_Up", "F5") because that is what the toolkits and
   the global key grab speak; nothing else in the system can turn them into
   something a user recognises. */
+ (NSString*) EAUsymbolForKeyEquivalent: (NSString*)keyEquivalent
{
  if ([keyEquivalent length] == 1)
    {
      unichar ch = [keyEquivalent characterAtIndex: 0];

      if (ch >= 'a' && ch <= 'z') { return [keyEquivalent uppercaseString]; }
      if (ch == 8)   { return @"⌫"; }   // Backspace
      if (ch == 127) { return @"⌫"; }
      if (ch == 27)  { return @"⎋"; }   // Escape
      if (ch == 9)   { return @"⇥"; }   // Tab
      if (ch == 13)  { return @"↵"; }   // Return
      if (ch == 32)  { return @"␣"; }   // Space
      return keyEquivalent;
    }

  NSString *lower = [keyEquivalent lowercaseString];
  if ([lower isEqualToString: @"left"])      { return @"←"; }
  if ([lower isEqualToString: @"right"])     { return @"→"; }
  if ([lower isEqualToString: @"up"])        { return @"↑"; }
  if ([lower isEqualToString: @"down"])      { return @"↓"; }
  if ([lower isEqualToString: @"page_up"])   { return @"⇞"; }
  if ([lower isEqualToString: @"page_down"]) { return @"⇟"; }
  if ([lower isEqualToString: @"home"])      { return @"↖"; }
  if ([lower isEqualToString: @"end"])       { return @"↘"; }
  if ([lower isEqualToString: @"insert"])    { return @"Ins"; }
  if ([lower isEqualToString: @"delete"])    { return @"⌦"; }
  if ([lower isEqualToString: @"escape"])    { return @"⎋"; }
  if ([lower isEqualToString: @"return"])    { return @"↵"; }
  if ([lower isEqualToString: @"tab"])       { return @"⇥"; }
  if ([lower isEqualToString: @"space"])     { return @"␣"; }
  if ([lower isEqualToString: @"backspace"]) { return @"⌫"; }

  return keyEquivalent;
}

- (NSString*) EAUconvertKeyEquivalentToMacStyle: (NSString*)keyEquivalent withModifiers: (NSUInteger)modifierMask
{
  if ([keyEquivalent length] == 0)
    {
      return keyEquivalent;
    }

  // Handle the old "#key" format, in which the modifier is part of the string
  if ([keyEquivalent hasPrefix: @"#"] && [keyEquivalent length] > 1)
    {
      NSString *key = [keyEquivalent substringFromIndex: 1];
      return [NSString stringWithFormat: @"⌘%@", [key uppercaseString]];
    }

  // Modifier symbols in Mac order: Control, Option, Command, Shift
  NSMutableString *result = [NSMutableString string];
  if (modifierMask & NSControlKeyMask)   { [result appendString: @"⌃"]; }
  if (modifierMask & NSAlternateKeyMask) { [result appendString: @"⌥"]; }
  if (modifierMask & NSCommandKeyMask)   { [result appendString: @"⌘"]; }
  if (modifierMask & NSShiftKeyMask)     { [result appendString: @"⇧"]; }

  [result appendString: [NSMenuItemCell EAUsymbolForKeyEquivalent: keyEquivalent]];

  NSDebugLog(@"NSMenuItemCell+Eau: Key equivalent '%@' with modifiers %lu shows as '%@'",
         keyEquivalent, (unsigned long)modifierMask, result);
  return result;
}

@end
