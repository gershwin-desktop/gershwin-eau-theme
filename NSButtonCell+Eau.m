/*
 * NSButtonCell+Eau.m
 * Eau Theme - Button Cell Enhancements
 *
 * This file uses the method swizzling pattern for NSButtonCell to:
 * 1. Intercept common_ret/common_retH images and hide them
 * 2. Automatically set buttons with these images as default buttons
 * 3. Enable pulsing animation for default buttons
 * 4. Make default buttons appear selected with highlighted border
 * 5. Ensure crash-safe operation even when windows/buttons cannot be found
 * While 2, 3, and 4 could be done by the application,
 * most applications will not do this, so we handle it here. 
 */

#import "NSCell+Eau.h"
#import "NSButtonCell+Eau.h"
#import "Eau+Button.h"
#import "AppearanceMetrics.h"
#import "Behaviors/NSButtonCell+GB.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>

// Prevent the specific "return" images from ever being drawn by intercepting common draw methods.
@interface NSImage(EauSuppressReturnImageDraw)
@end

@implementation NSImage(EauSuppressReturnImageDraw)

+ (void)load
{
  // Grand Central Dispatch may not be available in all build environments; use a simple synchronized guard.
  static BOOL EAU_swizzled = NO;
  @synchronized([NSImage class]) {
    if (EAU_swizzled) return;
    EAU_swizzled = YES;

    Class cls = [self class];
    Method orig, swiz;

    orig = class_getInstanceMethod(cls, @selector(drawAtPoint:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawAtPoint:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:fromRect:operation:fraction:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:fromRect:operation:fraction:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);

    orig = class_getInstanceMethod(cls, @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:));
    swiz = class_getInstanceMethod(cls, @selector(EAU_drawInRect:fromRect:operation:fraction:respectFlipped:hints:));
    if (orig && swiz) method_exchangeImplementations(orig, swiz);
  }
}

- (BOOL)EAU_isReturnImage
{
  NSString *name = [self name];
  if (!name) return NO;
  NSString *base = [name stringByDeletingPathExtension];
  return [base isEqualToString:@"common_ret"] || [base isEqualToString:@"common_retH"];
}

- (void)EAU_drawAtPoint:(NSPoint)point
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawAtPoint for %@", [self name]);
    return;
  }
  [self EAU_drawAtPoint:point];
}

- (void)EAU_drawInRect:(NSRect)rect
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect];
}

- (void)EAU_drawInRect:(NSRect)rect fromRect:(NSRect)srcRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect:fromRect:operation:fraction: for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect fromRect:srcRect operation:op fraction:delta];
}

- (void)EAU_drawInRect:(NSRect)rect fromRect:(NSRect)srcRect operation:(NSCompositingOperation)op fraction:(CGFloat)delta respectFlipped:(BOOL)respectFlipped hints:(NSDictionary *)hints
{
  if ([self EAU_isReturnImage]) {
    NSDebugLog(@"NSImage: Suppressing drawInRect:respectFlipped:hints: for %@", [self name]);
    return;
  }
  [self EAU_drawInRect:rect fromRect:srcRect operation:op fraction:delta respectFlipped:respectFlipped hints:hints];
}

@end

@implementation Eau(NSButtonCell)

/* A Return key equivalent is what makes a button the default one, so this is
 * where the cell learns to draw with the default-button colour.  GSTheme's own
 * implementation still runs first and hands the cell the common_ret image,
 * which -setImage: below hides. */
- (void) setKeyEquivalent: (NSString *)key forButtonCell: (NSButtonCell *)cell
{
  [super setKeyEquivalent: key forButtonCell: cell];
  if ([key isEqualToString: @"\r"])
    {
      [cell setIsDefaultButton: @YES];
    }
}

// Override image method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_image
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself EAUimage];
}

// Override alternateImage method using GSTheme method swizzling pattern
- (NSImage *) _overrideNSButtonCellMethod_alternateImage
{
  NSButtonCell *xself = (NSButtonCell*) self;
  return [xself EAUalternateImage];
}
@end

@implementation NSButtonCell(EauTheme)

/* Per-cell flags.  These used to be global sets of raw cell pointers, which
 * needed a -dealloc override to prune them - and that override shadowed
 * -[NSButtonCell dealloc], leaking the cell's alternate title, images, key
 * equivalent and sound.  Associated objects die with the cell, so the sets and
 * the -dealloc that maintained them are gone. */
static const void *kEAUProcessingReturnKey = &kEAUProcessingReturnKey;
static const void *kEAUReturnImageKey = &kEAUReturnImageKey;
static const void *kEAUPulsingKey = &kEAUPulsingKey;

+ (void)load
{
  // Swizzle -drawInteriorWithFrame:inView: so we can ignore return images for
  // layout calculations (prevents title shifting when mouse is pressed).
  Class cls = [NSButtonCell class];
  Method orig = class_getInstanceMethod(cls, @selector(drawInteriorWithFrame:inView:));
  Method swiz = class_getInstanceMethod(cls, @selector(EAU_drawInteriorWithFrame:inView:));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);

  // Swizzle -cellSize so buttons always request at least the minimum width
  // (METRICS_BUTTON_MIN_WIDTH), giving the pill shape enough horizontal room.
  orig = class_getInstanceMethod(cls, @selector(cellSize));
  swiz = class_getInstanceMethod(cls, @selector(EAU_cellSize));
  if (orig && swiz) method_exchangeImplementations(orig, swiz);
}

// Helper methods to track processing state
- (BOOL) isProcessingReturnButton
{
  return [objc_getAssociatedObject(self, kEAUProcessingReturnKey) boolValue];
}

- (void) setIsProcessingReturnButton:(BOOL)processing
{
  objc_setAssociatedObject(self, kEAUProcessingReturnKey,
                           processing ? [NSNumber numberWithBool: YES] : nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// The cell carries one of the return-arrow images that Eau suppresses.
- (BOOL) EAUhasSuppressedReturnImage
{
  return [objc_getAssociatedObject(self, kEAUReturnImageKey) boolValue];
}

- (void) EAUmarkSuppressedReturnImage
{
  objc_setAssociatedObject(self, kEAUReturnImageKey, [NSNumber numberWithBool: YES],
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Handle common_ret/common_retH images: hide them and enable button pulsing
- (NSImage *) EAUimage
{
  NSImage *originalImage = [super image];
  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
      
      if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                       [baseName isEqualToString:@"common_retH"]))
        {
          // Remember that this cell is using the suppressed return image so
          // we can treat layout differently while it's highlighted.
          [self EAUmarkSuppressedReturnImage];

          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setImage to handle common_ret/common_retH images
- (void) setImage:(NSImage *)image
{
  if (image) {
    NSString *imageName = [image name];
    NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
    
    if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                     [baseName isEqualToString:@"common_retH"])) {
      
      // Remember that this cell is using the suppressed return image so
      // we can treat layout differently while it's highlighted.
      [self EAUmarkSuppressedReturnImage];

      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        // Keep the guard set ACROSS enablePulsing: it re-drives setKeyEquivalent:,
        // which routes through GSTheme back into setImage: (the return-arrow image).
        // Clearing the flag before enablePulsing left that re-entry unguarded and
        // produced an infinite setImage:/setKeyEquivalent: recursion (stack overflow).
        [self enablePulsing];
        [self setIsProcessingReturnButton:NO];
      }
      
      return; // Don't set the image
    }
  }
  
  [super setImage:image];
}

// Handle common_ret/common_retH alternate images
- (NSImage *) EAUalternateImage
{
  NSImage *originalImage = nil;

  if ([self respondsToSelector:@selector(alternateImage)]) {
    originalImage = ((NSButtonCell *)self).alternateImage;
  }

  if (originalImage)
    {
      NSString *imageName = [originalImage name];
      NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
      
      if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                       [baseName isEqualToString:@"common_retH"]))
        {
          // Remember that this cell is using the suppressed return image so
          // we can treat layout differently while it's highlighted.
          [self EAUmarkSuppressedReturnImage];

          // Prevent infinite loops
          if (![self isProcessingReturnButton]) {
            [self setIsProcessingReturnButton:YES];
            [self setIsDefaultButton:@YES];
            [self enablePulsing];
            [self setIsProcessingReturnButton:NO];
          }
          
          return nil; // Hide the image
        }
    }
  
  return originalImage;
}

// Intercept setAlternateImage to handle common_ret/common_retH images
- (void) EAU_setAlternateImage:(NSImage *)alternateImage
{
  if (alternateImage) {
    NSString *imageName = [alternateImage name];
    NSString *baseName = imageName ? [imageName stringByDeletingPathExtension] : nil;
    
    if (baseName && ([baseName isEqualToString:@"common_ret"] || 
                     [baseName isEqualToString:@"common_retH"])) {
      // Remember that this cell is using the suppressed return image so
      // we can treat layout differently while it's highlighted.
      [self EAUmarkSuppressedReturnImage];

      // Prevent infinite loops
      if (![self isProcessingReturnButton]) {
        [self setIsProcessingReturnButton:YES];
        [self setIsDefaultButton:@YES];
        // Keep the guard set ACROSS enablePulsing: it re-drives setKeyEquivalent:,
        // which routes through GSTheme back into setImage: (the return-arrow image).
        // Clearing the flag before enablePulsing left that re-entry unguarded and
        // produced an infinite setImage:/setKeyEquivalent: recursion (stack overflow).
        [self enablePulsing];
        [self setIsProcessingReturnButton:NO];
      }
      
      return; // Don't set the image
    }
  }
  if ([self respondsToSelector:@selector(setAlternateImage:)]) {
    [(NSButtonCell *)self setAlternateImage:alternateImage];
  }
}

/* Mark the cell so the theme draws it with the pulsing default-button colour.
 *
 * Finding the window that should adopt this cell as its default button is the
 * button's job, not the cell's: -[NSButtonCell controlView] stays nil until the
 * cell has been drawn once, so a cell cannot reliably reach its window at the
 * moment the return image arrives.  -[NSButton gb_becomeWindowDefaultButton]
 * in GershwinBehaviors does it from the view side, where the window is known. */
- (void) enablePulsing
{
  /* -EAUimage runs from the drawing path, so for a cell that was decoded with
   * the return image still in place this is reached on every single draw.  Do
   * the one-off wiring once: -gb_adoptReturnKeyEquivalent marks the button
   * for display, and redrawing from inside a draw would spin. */
  if ([objc_getAssociatedObject(self, kEAUPulsingKey) boolValue])
    {
      return;
    }
  objc_setAssociatedObject(self, kEAUPulsingKey, [NSNumber numberWithBool: YES],
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);

  NSDebugLog(@"NSButtonCell+Eau: enablePulsing called for button cell %p", self);

  [self setIsDefaultButton:@YES];

  /* Answering Return is behavior, so GershwinBehaviors does the keyboard side;
   * the theme only knows that the cell shows the (hidden) return arrow. */
  if ([self respondsToSelector: @selector(gb_adoptReturnKeyEquivalent)])
    {
      [self gb_adoptReturnKeyEquivalent];
    }
}

// When highlighted, if this cell has a return icon image set internally, compute
// the title rect as if there was no image so the title doesn't shift while
// clicking. This mirrors NSCell's text layout and only applies for the highlighted
// state and when the stored images are the suppressed return images.
- (NSRect) titleRectForBounds:(NSRect)theRect
{
  BOOL hasReturnImage = [self EAUhasSuppressedReturnImage];

  if (hasReturnImage && [self isHighlighted]) {
    NSDebugLog(@"NSButtonCell+Eau: Suppressing layout image space for highlighted cell %p (return image), title rect adjusted", self);
    NSRect frame = [self drawingRectForBounds: theRect];
    if ([self isBordered] || [self isBezeled]) {
      frame.origin.x += 3;
      frame.size.width -= 6;
      frame.origin.y += 1;
      frame.size.height -= 2;
    }
    return frame;
  }

  return [super titleRectForBounds: theRect];
}

// Replace layout-influencing image data while drawing so buttons don't shift as if the
// return icon were present. This temporarily clears private ivars that hold the images
// only if those images are the return images, then calls the original implementation.
- (void) EAU_drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView*)controlView
{
  BOOL shouldRemoveImagePosition = NO;

  NSCellImagePosition oldPos = [self imagePosition];

  if ([self EAUhasSuppressedReturnImage] && oldPos != NSNoImage) {
    shouldRemoveImagePosition = YES;
  }

  if (shouldRemoveImagePosition) {
    @try {
      [self setImagePosition: NSNoImage];
    }
    @catch (NSException *e) {
      NSDebugLog(@"NSButtonCell+Eau: ERROR setting imagePosition to NSNoImage for cell %p: %@", self, e);
      shouldRemoveImagePosition = NO; // avoid restoring to wrong state
    }
  }

  // Call original implementation (swizzled). Keep this one guarded: it runs on
  // AppKit's display path, so an exception here must not escape into the draw
  // loop, and must not skip the imagePosition restore below (which would leave
  // the cell stuck at NSNoImage).
  @try {
    [self EAU_drawInteriorWithFrame:cellFrame inView:controlView];
  }
  @catch (NSException *e) {
    NSDebugLog(@"NSButtonCell+Eau: ERROR in EAU_drawInteriorWithFrame (original): %@", e);
  }
  if (shouldRemoveImagePosition) {
    [self setImagePosition: oldPos];

  }
}

// Ensure the cell is never narrower than its title text plus bezel padding,
// so translated strings (which can be much longer than the English source)
// always fit horizontally.  Also enforce at least METRICS_BUTTON_MIN_WIDTH
// for bezeled buttons so pill-shaped buttons have room around their text.
- (NSSize) EAU_cellSize
{
  NSSize size = [self EAU_cellSize]; // call original (swizzled)

  // Width needed for the title as actually rendered (using the cell's font)
  // plus horizontal bezel margins.  GNUstep's cellSize already adds border
  // + 6px, but recompute from the attributed title so the theme guarantees
  // translated text never clips regardless of the base implementation.
  if ([self respondsToSelector: @selector(attributedTitle)])
    {
      NSAttributedString *title = [self attributedTitle];
      if (title && [title length])
        {
          NSSize titleSize = [title size];
          GSThemeMargins m = [[GSTheme theme] buttonMarginsForCell: self
                                                             style: [self bezelStyle]
                                                             state: GSThemeNormalState];
          CGFloat minWidth = titleSize.width + m.left + m.right + 6 + 6;
          if (size.width < minWidth)
            size.width = minWidth;
        }
    }

  if (size.width < METRICS_BUTTON_MIN_WIDTH && [self isBezeled])
    {
      size.width = METRICS_BUTTON_MIN_WIDTH;
    }
  return size;
}

@end
