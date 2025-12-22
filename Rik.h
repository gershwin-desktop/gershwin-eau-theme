#import <AppKit/AppKit.h>
#import <Foundation/NSUserDefaults.h>
#import <GNUstepGUI/GSTheme.h>

// To enable debugging messages in the _overrideClassMethod_foo mechanism
#if 1
#define RIKLOG(args...) NSDebugLog(args)
#else
#define RIKLOG(args...)
#endif

@interface Rik: GSTheme
{
    id menuRegistry;
}
+ (NSColor *) controlStrokeColor;
- (void) drawPathButton: (NSBezierPath*) path
                     in: (NSCell*)cell
			            state: (GSThemeControlState) state;
@end


#import "Rik+Drawings.h"
