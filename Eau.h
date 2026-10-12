#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>
#import "NSTableView+Eau.h"

// Menu item horizontal padding in pixels. This value is the total horizontal
// padding applied to a menu item and is split equally between the left and
// right sides (e.g. 10.0 => 5 px on the left, 5 px on the right). The
// default of 10.0 was chosen to visually match typical GNUstep menu metrics
// on FreeBSD; in normal use this should remain a small, non-negative even
// number of pixels, usually in the range [4.0, 16.0].
#define EAU_MENU_ITEM_PADDING 10.0

// Loads GershwinBehaviors.bundle when GSAppKitUserBundles did not.
extern void EauEnsureBehaviorsLoaded(void);

@interface Eau: GSTheme
{
    NSColorList *editableSystemColors;
}
+ (NSColor *) controlStrokeColor;
- (void) invalidateScaleFactorCache;
- (CGFloat) menuItemIconSize;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;

/* Safely convert colors to calibrated RGB. Use this where code previously used
   colorUsingColorSpaceName: NSCalibratedRGBColorSpace to avoid exceptions when
   colors are in non-RGB color spaces (pattern, device, etc.). */
NSColor *EauSafeCalibratedRGB(NSColor *c);

@end

/* The bundle's code cannot be unloaded once the theme has been loaded, and the
 * +load swizzles in the Eau categories stay installed for the life of the
 * process.  Every swizzled method therefore asks this before doing anything
 * Eau-specific and otherwise chains straight to the implementation it
 * replaced, so another theme can take over without Eau's behaviour leaking
 * into it.  Set by -[Eau activate], cleared by -[Eau deactivate].
 * Swizzles in GershwinBehaviors.bundle (Behaviors/) are theme-independent and
 * deliberately do not ask. */
BOOL EauThemeIsActive(void);

/* Set by -[Eau activate] and -[Eau deactivate]; nothing else has any business
 * calling it. */
void EauSetThemeActive(BOOL flag);

/* Put the implementations GSTheme's -_override<Class>Method_<selector>
 * mechanism replaced back as they were before any theme ran.  See
 * EauThemeSwitch.m for why GSTheme's own bookkeeping is not enough. */
void EauRestoreOverriddenMethods(void);

/* Take the snapshot the above restores from.  Must run before the first
 * GSTheme instance of this bundle is built; -[Eau initWithBundle:] does it. */
void EauRecordOriginalOverriddenMethods(void);

/* Take Eau's focus-ring overlay out of a window (Eau+FocusFrame.m). */
void EauRemoveFocusOverlayFromWindow(NSWindow *win);

/* Drawing helpers — declared in Eau+Drawings.h category interface,
   implemented in Eau+Drawings.m and Eau+Button.m */
#import "Eau+Drawings.h"

