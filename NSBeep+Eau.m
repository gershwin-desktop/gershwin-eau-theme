/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NSApplication beep override for Eau theme
 * Plays the configured alert sound instead of system beep
 */

#import <AppKit/AppKit.h>

@implementation NSApplication (EauBeep)

+ (void)load {
    NSLog(@"[Eau] NSApplication(EauBeep) +load");
}


// Override the beep method to play configured alert sound
- (void)beep
{
    static BOOL isPlaying = NO;
    
    // Prevent recursive calls
    if (isPlaying) {
        NSLog(@"[Eau] Re-entrant beep ignored");
        return;
    }
    
    isPlaying = YES;
    NSLog(@"[Eau] -beep called");
    
    @autoreleasepool {
        // Load preferences for alert sound
        NSString *prefsPath = [NSHomeDirectory() stringByAppendingPathComponent:
                              @".config/gershwin/sound-defaults.plist"];
        NSLog(@"[Eau] prefsPath: %@", prefsPath);
        
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
        
        if (prefs) {
            NSLog(@"[Eau] Loaded prefs");
            NSString *alertSoundName = [prefs objectForKey:@"alertSound"];
            
            if (alertSoundName) {
                NSLog(@"[Eau] alertSound: %@", alertSoundName);
                // Search for the sound file
                NSArray *soundPaths = @[
                    @"/System/Library/Sounds",
                    @"/usr/share/sounds",
                    @"/usr/local/share/sounds",
                    [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Sounds"]
                ];
                
                NSArray *extensions = @[@"aiff", @"aif", @"wav", @"au", @"snd"];
                
                for (NSString *basePath in soundPaths) {
                    for (NSString *ext in extensions) {
                        NSString *soundPath = [basePath stringByAppendingPathComponent:
                                             [alertSoundName stringByAppendingPathExtension:ext]];
                        
                        if ([[NSFileManager defaultManager] fileExistsAtPath:soundPath]) {
                            NSLog(@"[Eau] Found sound at %@", soundPath);
                            // Play the sound using NSSound
                            NSSound *sound = [[NSSound alloc] initWithContentsOfFile:soundPath
                                                                        byReference:YES];
                            if (sound) {
                                NSLog(@"[Eau] Playing sound %@", soundPath);
                                [sound play];
                                [sound release];
                                isPlaying = NO;
                                return;
                            } else {
                                NSLog(@"[Eau] Failed to init NSSound for %@", soundPath);
                            }
                        }
                    }
                }
                NSLog(@"[Eau] No sound file found for %@ in sound paths", alertSoundName);
            } else {
                NSLog(@"[Eau] alertSound key missing in prefs");
            }
        } else {
            NSLog(@"[Eau] No prefs found at %@", prefsPath);
        }
        
        // Fall back to system beep (PC speaker or /dev/console)
        NSLog(@"[Eau] Falling back to system bell");
        printf("\a");
        fflush(stdout);
    }
    
    isPlaying = NO;
}

@end
