#import "Eau.h"
#import <AppKit/NSPopUpButton.h>

@interface NSPopUpButton (EauTheme)
- (void) EAUmouseDown: (NSEvent*)theEvent;
@end

@implementation Eau (NSPopUpButton)
- (void) _overrideNSPopUpButtonMethod_mouseDown: (NSEvent*)theEvent {
  NSDebugLog(@"_overrideNSPopUpButtonMethod_mouseDown:");
  NSPopUpButton *xself = (NSPopUpButton*)self;
  [xself EAUmouseDown:theEvent];
}
@end

@implementation NSPopUpButton (EauTheme)

- (void) EAUmouseDown: (NSEvent*)theEvent
{ 
  [_cell trackMouse: theEvent 
	     inRect: [self bounds] 
	     ofView: self 
       untilMouseUp: NO];
}

@end

