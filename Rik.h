#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>

// To enable debugging messages in the _overrideClassMethod_foo mechanism
#if 1
#define RIKLOG(args...) NSDebugLog(args)
#else
#define RIKLOG(args...)
#endif

// Menu item horizontal padding (total padding, split equally left and right)
#define RIK_MENU_ITEM_PADDING 10.0

@interface Rik: GSTheme
{
    id menuRegistry;
}
+ (NSColor *) controlStrokeColor;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;
- (BOOL) _isDBusAvailable;
@end


#import "Rik+Drawings.h"
