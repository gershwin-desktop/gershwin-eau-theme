#import <AppKit/AppKit.h>

@interface AppDelegate : NSObject
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSLog(@"App finished launching, showing NSPanel as dialog...");
    
    NSPanel *dialog = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,320,120)
                                                  styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    [dialog setTitle:@"NSDialog Test"];
    
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20,60,280,24)];
    [label setStringValue:@"This is a test of NSPanel as a dialog window."];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [[dialog contentView] addSubview:label];
    
    NSButton *okButton = [[NSButton alloc] initWithFrame:NSMakeRect(120,20,80,32)];
    [okButton setTitle:@"OK"];
    [okButton setButtonType:NSMomentaryPushInButton];
    [okButton setBezelStyle:NSRoundedBezelStyle];
    [okButton setTarget:NSApp];
    [okButton setAction:@selector(stopModal:)];
    [[dialog contentView] addSubview:okButton];
    
    [dialog center];
    NSInteger result = [NSApp runModalForWindow:dialog];
    NSLog(@"NSDialog result: %ld", result);
    [dialog orderOut:nil];
    
    [NSApp terminate:nil];
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
      [NSApplication sharedApplication];
        
      AppDelegate *delegate = [[AppDelegate alloc] init];
      [NSApp setDelegate: delegate];
        
      [NSApp run];
    }
    return 0;
}
