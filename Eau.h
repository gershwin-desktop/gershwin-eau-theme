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

/* Drawing helpers — declared in Eau+Drawings.h category interface,
   implemented in Eau+Drawings.m and Eau+Button.m */
#import "Eau+Drawings.h"

