#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#import "GBTheme.h"
#import "GBThemeHooks+Font.h"

/*
 * NSFont+GB.m - font resolution robustness, theme-independent
 *
 * Guards against two GNUstep/fontconfig integration gaps that any theme
 * would otherwise hit: a resolved family that is not actually installed,
 * and a resolved face at the wrong weight. Neither depends on which family
 * a theme chooses to draw with.  The typography itself (a fixed menu font
 * size, which weights to enforce) is the theme's call, asked for through the
 * optional hooks in GBThemeHooks+Font.h: under a theme without them, callers
 * keep the size they asked for and fontconfig's weight is trusted.
 */

/* Sizes and weights are asked for on every call rather than cached, because
 * the user can switch themes at run time and the answer changes with it. */
static CGFloat GBMenuFontSize(CGFloat requested)
{
  id theme = GBThemeIfResponds(@selector(gbMenuFontSize));
  CGFloat size = theme ? [theme gbMenuFontSize] : 0.0;
  return (size > 0.0) ? size : requested;
}

static NSInteger GBSystemFontWeight(BOOL bold)
{
  id theme = GBThemeIfResponds(@selector(gbSystemFontWeight:));
  return theme ? [theme gbSystemFontWeight: bold] : 0;
}

// Category on NSFont used for method swizzling
@interface NSFont (GBSwizzling)
+ (NSFont *)gb_menuBarFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_menuFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_systemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_boldSystemFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_controlContentFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_userFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_userFixedPitchFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_titleBarFontOfSize:(CGFloat)fontSize;
+ (NSFont *)gb_fontWithName:(NSString *)name size:(CGFloat)size;
+ (NSFont *)gb_fontOrDefault:(NSFont *)font size:(CGFloat)size;
+ (NSFont *)gb_fontOrDefault:(NSFont *)font size:(CGFloat)size weight:(NSInteger)weight;
@end

@implementation NSFont (GBSwizzling)

// GNUstep resolves the "system font" to a fixed family name such as
// Helvetica. On hosts where fontconfig cannot map that name the resulting
// NSFont object has no glyphs and text drawing fails with "Glyph generation
// with no font".  We make text rendering resilient: whenever the resolved
// font references a family that is not actually available on this system, we
// log a warning and substitute any available sans-serif family instead.
//
// TODO: Upstream to GNUstep - the font backend should itself verify a
// resolved family exists via fontconfig and fall back before handing out an
// NSFont with no glyphs, instead of every caller needing this guard.

// Memoized list of available font families.  The fontconfig family set does
// not change during a run, and re-enumerating it on every call is expensive:
// building a menu creates one NSMenuItemCell per item and each one resolves
// its font, so without memoizing, a menu rebuild spends its time in
// fontconfig (FcFontSort/FcFontSetSort) instead of drawing - the source of
// Menu.app's repeated CPU bursts while its menu bar is rebuilt.
static NSArray *GBFontFamilies(void)
{
  static NSArray *families = nil;
  if (families == nil)
    families = [[NSFontManager sharedFontManager] availableFontFamilies];
  return families;
}

static NSString *GBAvailableFamily(void)
{
  static NSArray *order = nil;
  if (order == nil)
    order = @[@"Inter", @"Nimbus Sans", @"DejaVu Sans", @"Liberation Sans",
              @"Arial", @"Helvetica", @"Clean", @"Luxi Sans", @"URW Gothic"];

  NSArray *families = GBFontFamilies();
  for (NSString *pattern in order)
    for (NSString *fam in families)
      if ([fam rangeOfString:pattern options:NSCaseInsensitiveSearch]
            .location != NSNotFound)
        return fam;

  return ([families count] > 0) ? [families objectAtIndex:0] : nil;
}

// Memoized substitute font, resolved once per process.  Built via the
// (never swizzled) NSFontManager family API so that building it can never
// re-enter our own swizzled NSFont constructors and cause recursion.
static NSFont *GBFallbackFont(void)
{
  static NSFont *fallback = nil;
  if (fallback == nil)
    {
      NSString *family = GBAvailableFamily();
      if (family != nil)
        fallback = [[NSFontManager sharedFontManager]
                     fontWithFamily:family traits:0 weight:5 size:13.0];
      }
  return fallback;
}

+ (NSFont *)gb_fontOrDefault:(NSFont *)font size:(CGFloat)size
{
  return [self gb_fontOrDefault: font size: size weight: 0];
}

/* Like gb_fontOrDefault:size:, but when weight > 0 rebuilds the face from the
 * resolved family at that weight instead of trusting the base font.  GNUstep
 * resolves the "system font" to whatever face fontconfig picks, which inside
 * the Menu process was the wrong weight (systemFontOfSize:11 came back
 * Inter-Bold, boldSystemFontOfSize:13 came back Inter-Medium).  The system
 * font contract is regular for systemFontOfSize: and bold for
 * boldSystemFontOfSize:, so those two entry points enforce the weight the
 * theme names (Eau: 6 / 9) to restore it, while every other selector keeps
 * its base face.
 *
 * TODO: Upstream to GNUstep - systemFontOfSize:/boldSystemFontOfSize: should
 * guarantee the regular/bold weight contract themselves when resolving
 * through fontconfig, instead of returning whatever weight fontconfig's
 * closest match happens to pick. */
+ (NSFont *)gb_fontOrDefault:(NSFont *)font size:(CGFloat)size weight:(NSInteger)weight
{
  // Cache the resolved font per (family, weight, size): a menu rebuild creates
  // one NSMenuItemCell per item and each one re-runs fontconfig matching
  // (FcFontSort) here, which is what makes Menu.app's CPU spike while menus
  // are rebuilt.  The resolution is deterministic, so caching is safe.
  static NSMutableDictionary *cache = nil;
  if (cache == nil)
    cache = [NSMutableDictionary dictionary];

  NSString *fontFamily = [font familyName];
  NSString *cacheKey = [NSString stringWithFormat: @"%@\v%ld\v%.1f",
    fontFamily ?: @"", (long)weight, size];
  NSFont *hit = [cache objectForKey: cacheKey];
  if (hit != nil)
    return hit;

  BOOL enforceWeight = (weight > 0);
  NSFont *resolved = nil;
  // If the resolved font references a family that really exists on the
  // system, keep it (preserves bold/italic and the intended look).
  if (fontFamily != nil)
    {
      NSArray *families = GBFontFamilies();
      for (NSString *fam in families)
        if ([fam isEqualToString:fontFamily])
          {
            if (enforceWeight)
              {
                // Rebuild at the requested weight rather than round-tripping
                // the base face (which may already be the wrong weight).
                NSUInteger traits = (weight >= 7) ? NSBoldFontMask : 0;
                resolved = [[NSFontManager sharedFontManager]
                             fontWithFamily: fontFamily
                                     traits: traits
                                     weight: weight
                                       size: size];
              }
            else
              {
                NSFontDescriptor *d = [font fontDescriptor];
                resolved = [NSFont fontWithDescriptor: d size: size];
              }
            break;
          }
      // Fall through: family is not reported as available.
    }

  if (resolved == nil)
    {
      // Log once, then fall back to any available sans-serif family so that
      // drawing is guaranteed to work as long as a single font is installed.
      static BOOL warned = NO;
      if (!warned)
        {
          warned = YES;
          NSLog(@"GershwinBehaviors: requested UI font family '%@' is not "
                @"available on this system; using '%@' instead.",
                fontFamily ?: @"(system default)",
                GBAvailableFamily() ?: @"(none)");
        }

      NSString *family = GBAvailableFamily();
      NSFont *usable = (family != nil) ? GBFallbackFont() : nil;
      if (usable == nil && font != nil)
        usable = font;

      if (enforceWeight && usable != nil)
        {
          // Apply the requested weight to the fallback family too.
          NSUInteger traits = (weight >= 7) ? NSBoldFontMask : 0;
          resolved = [[NSFontManager sharedFontManager]
                       fontWithFamily: [usable familyName]
                               traits: traits
                               weight: weight
                                 size: size];
        }
      if (resolved == nil && usable != nil)
        {
          NSFontDescriptor *desc = [usable fontDescriptor];
          resolved = [NSFont fontWithDescriptor: desc size: size];
        }
    }

  if (resolved != nil)
    [cache setObject: resolved forKey: cacheKey];
  return resolved;
}

+ (NSFont *)gb_menuBarFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_menuBarFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:GBMenuFontSize(fontSize)];
}

+ (NSFont *)gb_menuFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_menuFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:GBMenuFontSize(fontSize)];
}

+ (NSFont *)gb_systemFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_systemFontOfSize:fontSize];
  /* The system font is non-bold by contract; the theme may enforce it so a
   * fontconfig mis-resolution cannot render regular text bold. */
  return [self gb_fontOrDefault: base size: fontSize weight: GBSystemFontWeight(NO)];
}

+ (NSFont *)gb_boldSystemFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_boldSystemFontOfSize:fontSize];
  /* The bold system font must be bold; the theme may enforce it so a
   * fontconfig mis-resolution cannot render the headline weight regular. */
  return [self gb_fontOrDefault: base size: fontSize weight: GBSystemFontWeight(YES)];
}

+ (NSFont *)gb_controlContentFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_controlContentFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:fontSize];
}

+ (NSFont *)gb_userFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_userFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:fontSize];
}

+ (NSFont *)gb_userFixedPitchFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_userFixedPitchFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:fontSize];
}

+ (NSFont *)gb_fontWithName:(NSString *)name size:(CGFloat)size
{
  NSFont *base = [self gb_fontWithName:name size:size];
  if (base == nil)
    {
      // The requested font name does not resolve to anything on this system;
      // use the fallback sans-serif font so callers never receive nil.  The
      // fallback is built once at a fixed size, so it is rebuilt at the size
      // that was asked for: callers such as font panels or video titles
      // would otherwise get 13 pt text whatever size they chose.
      NSFont *usable = GBAvailableFamily() ? GBFallbackFont() : nil;
      if (usable == nil)
        return nil;
      return [NSFont fontWithDescriptor: [usable fontDescriptor] size: size];
    }
  return base;
}

+ (NSFont *)gb_titleBarFontOfSize:(CGFloat)fontSize
{
  NSFont *base = [self gb_titleBarFontOfSize:fontSize];
  return [self gb_fontOrDefault:base size:fontSize];
}

@end

// Constructor to set up swizzling
__attribute__((constructor))
static void GBSwizzleFonts(void)
{
  Class fontClass = [NSFont class];
  if (fontClass == 0) return;

  /* Collect the selector pairs at runtime (sel_registerName is not a
     compile-time constant, so it cannot appear in a static initializer). */
  SEL origSwaps[] = {
    sel_registerName("menuBarFontOfSize:"),
    sel_registerName("menuFontOfSize:"),
    sel_registerName("systemFontOfSize:"),
    sel_registerName("boldSystemFontOfSize:"),
    sel_registerName("controlContentFontOfSize:"),
    sel_registerName("userFontOfSize:"),
    sel_registerName("userFixedPitchFontOfSize:"),
    sel_registerName("titleBarFontOfSize:"),
    sel_registerName("fontWithName:size:"),
  };
  SEL swzSwaps[] = {
    @selector(gb_menuBarFontOfSize:),
    @selector(gb_menuFontOfSize:),
    @selector(gb_systemFontOfSize:),
    @selector(gb_boldSystemFontOfSize:),
    @selector(gb_controlContentFontOfSize:),
    @selector(gb_userFontOfSize:),
    @selector(gb_userFixedPitchFontOfSize:),
    @selector(gb_titleBarFontOfSize:),
    @selector(gb_fontWithName:size:),
  };
  int count = sizeof(origSwaps) / sizeof(origSwaps[0]);
  for (int i = 0; i < count; i++)
    {
      Method original = class_getClassMethod(fontClass, origSwaps[i]);
      Method swz      = class_getClassMethod(fontClass, swzSwaps[i]);
      if (original != 0 && swz != 0
          && method_getImplementation(original)
               != method_getImplementation(swz))
        method_exchangeImplementations(original, swz);
    }
}
