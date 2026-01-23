/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * NSApplication beep override for Eau theme
 * Plays the configured alert sound instead of system beep
 */

#import <AppKit/AppKit.h>
#import "Eau.h"

@implementation NSApplication (EauBeep)

+ (void)load {
    EAULOG(@"NSApplication(EauBeep) +load");
}


// Override the beep method to play configured alert sound
- (void)beep
{
    static BOOL isPlaying = NO;
    
    // Prevent recursive calls
    if (isPlaying) {
        EAULOG(@"Re-entrant beep ignored");
        return;
    }
    
    isPlaying = YES;
    EAULOG(@"-beep called");
    
    @autoreleasepool {
        // Load preferences for alert sound
        NSString *prefsPath = [NSHomeDirectory() stringByAppendingPathComponent:
                              @".config/gershwin/sound-defaults.plist"];
        EAULOG(@"prefsPath: %@", prefsPath);
        
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
        
        if (prefs) {
            EAULOG(@"Loaded prefs");
            NSString *alertSoundName = [prefs objectForKey:@"alertSound"];
            
            if (alertSoundName) {
                EAULOG(@"alertSound: %@", alertSoundName);
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
                            EAULOG(@"Found sound at %@", soundPath);
                            // Play the sound using NSSound
                            NSSound *sound = [[NSSound alloc] initWithContentsOfFile:soundPath
                                                                        byReference:YES];
                            if (sound) {
                                EAULOG(@"Playing sound %@", soundPath);
                                [sound play];
                                isPlaying = NO;
                                return;
                            } else {
                                EAULOG(@"Failed to init NSSound for %@", soundPath);
                            }
                        }
                    }
                }
                EAULOG(@"No sound file found for %@ in sound paths", alertSoundName);
            } else {
                EAULOG(@"alertSound key missing in prefs");
            }
        } else {
            EAULOG(@"No prefs found at %@", prefsPath);
        }
        
        // Fall back to system beep (PC speaker or /dev/console)
        EAULOG(@"Falling back to system bell");
        printf("\a");
        fflush(stdout);
    }
    
    isPlaying = NO;
}

@end
