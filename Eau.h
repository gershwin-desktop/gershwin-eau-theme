#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>
#import "NSTableView+Eau.h"

// To enable debugging messages in the _overrideClassMethod_foo mechanism
#if 1
#define EAULOG(args...) NSDebugLog(args)
#else
#define EAULOG(args...)
#endif

// Menu item horizontal padding in pixels. This value is the total horizontal
// padding applied to a menu item and is split equally between the left and
// right sides (e.g. 10.0 => 5 px on the left, 5 px on the right). The
// default of 10.0 was chosen to visually match typical GNUstep menu metrics
// on FreeBSD; in normal use this should remain a small, non-negative even
// number of pixels, usually in the range [4.0, 16.0].
#define EAU_MENU_ITEM_PADDING 10.0

@protocol GSGNUstepMenuClient <NSObject>
- (oneway void)activateMenuItemAtPath:(NSArray *)indexPath
                            forWindow:(NSNumber *)windowId;
@end

@interface Eau: GSTheme <GSGNUstepMenuClient>
{
    NSMutableDictionary *menuByWindowId;
    NSString *menuClientName;
    NSConnection *menuClientConnection;
    NSPort *menuClientReceivePort;
    NSConnection *menuServerConnection;
    id menuServerProxy;
    BOOL menuServerAvailable;
}
+ (NSColor *) controlStrokeColor;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;
@end


#import "Eau+Drawings.h"
