#import <AppKit/AppKit.h>

@interface AppDelegate : NSObject
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"App finished launching, showing alert...");
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: @"Test Alert"];
    [alert setInformativeText: @"Press Enter to click OK, or Escape to click Cancel.\n\nTry pressing Tab to cycle between buttons."];
    [alert addButtonWithTitle: @"OK"];
    [alert addButtonWithTitle: @"Cancel"];
    
    NSInteger result = [alert runModal];
    NSLog(@"NSAlert result: %ld", result);
    [alert release];
    
    [NSApp terminate: nil];
}
@end

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [NSApp setDelegate: delegate];
    
    [NSApp run];
    
    [delegate release];
    [pool release];
    return 0;
}
