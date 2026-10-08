#import <Foundation/Foundation.h>

@interface GBMenuRelaunchManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)captureMenuProcessSnapshotIfAvailable;
- (void)relaunchMenuProcessIfSnapshotAvailable;

@end
