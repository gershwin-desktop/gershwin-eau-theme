#import "NSUserDefaults+EauSystemFallback.h"
#import <objc/runtime.h>

/*
 This category implements a small, conservative fallback mechanism for
 -objectForKey: that attempts to return values from system-wide
 preference plists when the normal per-user NSUserDefaults lookup returns nil.

 What we're doing
 ----------------
 - Swizzle -objectForKey: to call the original implementation first.
 - If that returns nil, enumerate the contents of /System/Library/Preferences
   and check every *.plist for the requested key (with an app-specific
   <bundle-id>.plist checked first when present), falling back to
   .GlobalPreferences.plist and GlobalPreferences.plist.

 Why this approach
 ------------------
 - In the current environment the standard defaults machinery appears to
   resolve only user preferences (~/Library/Preferences). Some system-supplied
   defaults live under /System/Library/Preferences; this gives the Eau theme
   a way to observe those defaults for apps that do not provide a user value.
 - Doing this as a category keeps the change local to Eau (no system library
   rebuild), and is simple to add/remove for testing or distribution.

 Alternatives & trade-offs
 -------------------------
 - Swizzle other APIs or the +[NSUserDefaults standardUserDefaults] factory to
   return a proxy that merges sources. This can be cleaner for caching but
   requires careful compatibility handling.
 - Intercept CFPreferences* APIs (e.g., CFPreferencesCopyAppValue) by
   rebinding C symbols (fishhook) — this is more comprehensive because it
   covers code that bypasses Objective-C, but it requires a process-wide
   injection mechanism (dylib preload, LaunchAgent, etc.).
 - Use LD_PRELOAD / DYLD_INSERT_LIBRARIES to inject a dylib into all
   processes to ensure system-wide coverage (subject to SIP/AMFI on macOS).
 - Patch the underlying preferences implementation or rebuild the system
   frameworks (most invasive, but globally correct).

 Caveats & notes
 ----------------
 - Performance: this implementation reads plist files on misses which may be
   slower than in-memory cache-backed NSUserDefaults. If needed, add a small
   in-memory cache or watch for file changes to invalidate cached values.
 - Caching & semantics: NSUserDefaults often caches values; swizzling
   -objectForKey: may not affect code that reads cached values directly. If
   tests show cache-related inconsistencies, consider swizzling additional
   entry points or providing a proxy that merges sources up front.
 - Thread-safety: file I/O here is synchronous. If contention is a concern,
   perform lookup on a serial queue or add appropriate synchronization.
 - Scope: this category only affects processes that load the Eau theme bundle.
   To cover all apps, the code must be loaded into each target process via an
   injection mechanism (see Alternatives above).
 - Permissions/Sandboxing: reading /System/Library/Preferences is usually
   allowed for read-only.

 Testing & deployment
 --------------------
 - Add unit tests that create temporary plists in a test prefs dir, ensure
   lookup order (app plist -> other plists -> global) behaves as expected.
 - Consider logging (conditional on a debug flag) to help diagnose lookup
   failures during test runs.
 - If broader coverage is needed, we should prototype a fishhook-based dylib
   and a safe injection mechanism for the target environment.
*/

@implementation NSUserDefaults (EauSystemFallback)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = [self class];
        Method orig = class_getInstanceMethod(cls, @selector(objectForKey:));
        Method new = class_getInstanceMethod(cls, @selector(eau_objectForKey:));
        if (orig && new) {
            method_exchangeImplementations(orig, new);
        }
    });
}

- (id)eau_objectForKey:(NSString *)key {
    // Call original -objectForKey: via the swapped selector
    id val = [self eau_objectForKey:key];
    if (val) return val;

    // Fallback to system-wide preferences plist(s)
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];

    // Build a deduped ordered list of all .plist files in /System/Library/Preferences,
    // with the app-specific plist first when present.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *prefsDir = @"/System/Library/Preferences";
    NSMutableOrderedSet *pathsSet = [NSMutableOrderedSet orderedSet];

    if (bundleID) {
        NSString *appPlist = [prefsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", bundleID]];
        [pathsSet addObject:appPlist];
    }

    NSError *err = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:prefsDir error:&err];
    for (NSString *entry in contents ?: @[]) {
        if ([[entry pathExtension] isEqualToString:@"plist"]) {
            NSString *full = [prefsDir stringByAppendingPathComponent:entry];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:full isDirectory:&isDir] && !isDir) {
                [pathsSet addObject:full];
            }
        }
    }

    // Ensure global defaults are present as a fallback
    [pathsSet addObject:[prefsDir stringByAppendingPathComponent:@".GlobalPreferences.plist"]];
    [pathsSet addObject:[prefsDir stringByAppendingPathComponent:@"GlobalPreferences.plist"]];

    NSArray *paths = [pathsSet array];

    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d) {
            id v = d[key];
            if (v) return v;
        }
    }

    return nil;
}

@end
