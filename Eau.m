#import "Eau.h"

#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSWindowDecorationView.h>
#import "NSMenuItemCell+Eau.h"
#import "Eau+Button.h"
#import "AppearanceMetrics.h"

/* Process-wide GSScaleFactor cache used by the AppearanceMetrics macros;
 * reset by -invalidateScaleFactorCache for live scale-factor changes. */
CGFloat GSWScaleFactorValue = 0;

@interface Eau (NSWindowTitle)
+ (void)EAUswizzleNSWindowSetTitle;
+ (void)EAUswizzleGSStandardOffsets;
@end

/* Private window-decoration methods implemented in Eau+WindowDecoration.m */
@interface Eau (EauWindowDecoration)
- (void)invalidateTitleTextAttributes;
@end

/* Only one Eau instance is the active theme at a time.  GSTheme creates a
 * fresh instance on every +setTheme:, and the old one can outlive the switch,
 * so the flag is tied to the instance that last activated rather than to
 * "an Eau exists". */
static __unsafe_unretained Eau *gActiveEauTheme = nil;

// Implementation of safe color conversion helper
NSColor *EauSafeCalibratedRGB(NSColor *c)
{
  if (!c) return nil;

  @try {
    if ([c respondsToSelector:@selector(colorUsingColorSpaceName:)]) {
      NSColor *rgb = [c colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
      if (rgb) return rgb;
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: conversion threw: %@, falling back", ex);
  }

  // Try grayscale fallback
  @try {
    if ([c respondsToSelector:@selector(whiteComponent)]) {
      CGFloat w = [c whiteComponent];
      CGFloat a = ([c respondsToSelector:@selector(alphaComponent)] ? [c alphaComponent] : 1.0);
      return [NSColor colorWithCalibratedWhite:w alpha:a];
    }
  } @catch (NSException *ex) {
    NSLog(@"EauSafeCalibratedRGB: whiteComponent threw: %@, falling back", ex);
  }

  // Final fallback: light control background
  return [NSColor colorWithCalibratedWhite:0.95 alpha:1.0];
}

@implementation Eau

/* Reset the cached GSScaleFactor so the next render picks up a live change. */
- (void)invalidateScaleFactorCache
{
  GSWScaleFactorInvalidate();
  [self invalidateTitleTextAttributes];
}

/* Maximum size for the icon shown in front of a menu item (the image column,
 * used for application and preference-pane icons).  Icons are scaled down to
 * fit this box, never up, so a large app bundle icon renders small. */
- (CGFloat) menuItemIconSize
{
  return 18.0;
}

+ (void)load
{
  // Swizzle NSWindow setTitle: to add middle-ellipsis truncation for long titles
  [self EAUswizzleNSWindowSetTitle];

  // Match GNUstep's window frame offsets to the WM's real frame (no 1px
  // border in compositor mode) so window geometry round-trips pixel-exact.
  [self EAUswizzleGSStandardOffsets];
}

- (id)initWithBundle:(NSBundle *)bundle
{
  NSDebugLog(@"Eau: >>> initWithBundle ENTRY (before super init)");
  EauEnsureBehaviorsLoaded();

  /* Before GSTheme looks at this class' override methods for the first time,
     so that what it replaces is on record. */
  EauRecordOriginalOverriddenMethods();

  if ((self = [super initWithBundle:bundle]) != nil)
    {
      NSDebugLog(@"Eau: >>> initWithBundle after super init, self=%p", self);
      NSDebugLog(@"Eau: Initializing theme with bundle: %@", bundle);

      // Ensure alternating row background color is visible in Eau theme
      // Note: System color list may be read-only, so we wrap in try-catch
      NSDebugLog(@"Eau: >>> About to check system color list");
      @try
        {
          NSColorList *systemColors = [NSColorList colorListNamed: @"System"];
          NSDebugLog(@"Eau: >>> System color list: %p, isEditable: %d",
                 systemColors, systemColors ? [systemColors isEditable] : -1);
          if (systemColors != nil && [systemColors isEditable])
            {
              NSDebugLog(@"Eau: >>> Setting alternateRowBackgroundColor");
              // Light gray with a touch of blue
              [systemColors setColor: [NSColor colorWithCalibratedRed: 0.94
                                                                 green: 0.95
                                                                  blue: 0.97
                                                                 alpha: 1.0]
                               forKey: @"alternateRowBackgroundColor"];
              NSDebugLog(@"Eau: >>> alternateRowBackgroundColor set successfully");
            }
          else
            {
              NSDebugLog(@"Eau: >>> Skipping color list modification (nil or not editable)");
            }
        }
      @catch (NSException *exception)
        {
          NSDebugLog(@"Eau: Could not set alternating row color: %@", [exception reason]);
        }
      NSDebugLog(@"Eau: >>> initWithBundle EXIT");
    }
  return self;
}

#pragma mark - Theme activation

/* Everything Eau does beyond plain drawing - the swizzles in the category
   files - is switched on here and off in -deactivate, so another theme can
   take over in a running application.

   The Menu.app IPC is NOT started or stopped here (Eau used to connect to
   Menu.app before [super activate] and, on -deactivate, withdraw its windows
   and hand the bar back with -setMain:).
   It lives in GershwinBehaviors.bundle (Behaviors/GBMenuClient.m,
   Behaviors/GSTheme+GBMenu.m) and stays on under every theme, so a theme
   switch neither disconnects from Menu.app nor brings back the in-app bar. */
- (void) activate
{
  gActiveEauTheme = self;
  EauSetThemeActive(YES);
  [super activate];
}

- (void) deactivate
{
  if (gActiveEauTheme == self)
    {
      gActiveEauTheme = nil;
      EauSetThemeActive(NO);
    }

  [super deactivate];

  /* GSTheme restores whatever it believed the previous implementations were;
     that belief is wrong whenever this instance was built while another Eau
     instance was already active, so put the real originals back.  What Eau
     put into live windows - the title bar buttons, the resize grip - is taken
     out by EauThemeSwitchWatcher when the incoming theme activates, which is
     the only moment replacements for them can be asked for. */
  EauRestoreOverriddenMethods();
}

/* -[NSColor themeDidActivate:] completes a theme's system colour list with the
   defaults the theme does not define, and raises
   NSColorListNotEditableException when the list came straight out of a
   read-only bundle - which cuts that method short, before it announces
   NSSystemColorsDidChangeNotification, on every single activation.  Hand out a
   copy that can take those additions. */
- (NSColorList *) colors
{
  NSColorList *list = [super colors];
  NSEnumerator *enumerator;
  NSString *key;

  if (list == nil || [list isEditable])
    {
      return list;
    }

  if (editableSystemColors == nil)
    {
      editableSystemColors = [[NSColorList alloc] initWithName: [list name]];
      enumerator = [[list allKeys] objectEnumerator];
      while ((key = [enumerator nextObject]) != nil)
        {
          [editableSystemColors setColor: [list colorWithKey: key]
                                  forKey: key];
        }
    }
  return editableSystemColors;
}

+ (NSColor *) controlStrokeColor
{

  return [NSColor colorWithCalibratedRed: 0.4
                                   green: 0.4
                                    blue: 0.4
                                   alpha: 1];
}

- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state
{
  NSColor	*backgroundColor = [self buttonColorInCell: cell forState: state];
  NSColor* strokeColorButton = [Eau controlStrokeColor];
  NSGradient* buttonBackgroundGradient = [self _bezelGradientWithColor: backgroundColor];
  [buttonBackgroundGradient drawInBezierPath: path angle: -90];
  [strokeColorButton setStroke];
  [path setLineWidth: 1];
  [path stroke];
}

/**
 * Override GSTheme's keyForKeyEquivalent: to convert GNUstep key equivalent
 * strings to Mac-style symbols with Shift shown after Command.
 *
 * The NSMenuItemCell _keyEquivalentString produces strings like "/#s" where
 * modifiers are single-character codes (^=Control, +=Alternate, /=Shift, #=Command)
 * ordered Control → Alternate → Shift → Command → Key.
 *
 * This override converts to Mac Unicode symbols (⌃⌥⌘⇧) and reorders to
 * Control → Alternate → Command → Shift → Key.
 */
- (NSString *) keyForKeyEquivalent: (NSString *)aString
{
  if (!aString || [aString length] == 0)
    {
      return aString;
    }

  // Parse standard GNUstep modifier codes from the front of the string
  //
  // Format: [^][+][/][#]key
  //         ^ = Control   += Alternate/Option   /= Shift   # = Command
  NSUInteger pos = 0;
  NSUInteger len = [aString length];
  BOOL hasControl = NO;
  BOOL hasAlternate = NO;
  BOOL hasShift = NO;
  BOOL hasCommand = NO;

  while (pos < len)
    {
      unichar ch = [aString characterAtIndex: pos];
      if (ch == '^')   { hasControl = YES;  pos++; }
      else if (ch == '+') { hasAlternate = YES; pos++; }
      else if (ch == '/') { hasShift = YES;    pos++; }
      else if (ch == '#') { hasCommand = YES;  pos++; }
      else { break; }
    }

  // Remaining characters are the key name
  NSString *key = [aString substringFromIndex: pos];

  // Build Mac-style string: Control ⌃ → Option ⌥ → Command ⌘ → Shift ⇧ → Key
  NSMutableString *result = [NSMutableString string];
  if (hasControl)  { [result appendString: @"⌃"]; }
  if (hasAlternate){ [result appendString: @"⌥"]; }
  if (hasCommand)  { [result appendString: @"⌘"]; }
  if (hasShift)    { [result appendString: @"⇧"]; }

  // Uppercase single-letter keys
  if ([key length] == 1)
    {
      unichar ch = [key characterAtIndex: 0];
      if (ch >= 'a' && ch <= 'z')
        {
          key = [key uppercaseString];
        }
    }

  [result appendString: key];
  return result;
}

@end
