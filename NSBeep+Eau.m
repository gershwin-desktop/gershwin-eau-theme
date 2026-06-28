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
    NSDebugLog(@"NSApplication(EauBeep) +load");
}


// Override the beep method to play configured alert sound
- (void)beep
{
    static BOOL isPlaying = NO;

    // Prevent recursive calls
    if (isPlaying) {
        NSDebugLog(@"Re-entrant beep ignored");
        return;
    }

    isPlaying = YES;
    NSDebugLog(@"-beep called");

    @autoreleasepool {
        // Load preferences for alert sound
        NSString *prefsPath = [NSHomeDirectory() stringByAppendingPathComponent:
                              @".config/gershwin/sound-defaults.plist"];
        NSDebugLog(@"prefsPath: %@", prefsPath);

        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];

        if (prefs) {
            NSDebugLog(@"Loaded prefs");
            NSString *alertSoundName = [prefs objectForKey:@"alertSound"];
            NSNumber *alertVolume = [prefs objectForKey:@"alertVolume"];

            if (alertSoundName) {
                NSDebugLog(@"alertSound: %@", alertSoundName);
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
                            NSDebugLog(@"Found sound at %@", soundPath);
                            // Play the sound using NSSound
                            NSSound *sound = [[NSSound alloc] initWithContentsOfFile:soundPath
                                                                        byReference:YES];
                            if (sound) {
                                NSDebugLog(@"Playing sound %@", soundPath);
                                // Respect the alert volume setting
                                if (alertVolume) {
                                    [sound setVolume:[alertVolume floatValue]];
                                }
                                [sound play];
                                isPlaying = NO;
                                return;
                            } else {
                                NSDebugLog(@"Failed to init NSSound for %@", soundPath);
                            }
                        }
                    }
                }
                NSDebugLog(@"No sound file found for %@ in sound paths", alertSoundName);
            } else {
                NSDebugLog(@"alertSound key missing in prefs");
            }
        } else {
            NSDebugLog(@"No prefs found at %@", prefsPath);
        }

        // Fall back to system beep (PC speaker or /dev/console)
        NSDebugLog(@"Falling back to system bell");
        printf("\a");
        fflush(stdout);
    }

    isPlaying = NO;
}

@end
