#import <Foundation/Foundation.h>

@interface EauMenuRelaunchManager : NSObject
+ (instancetype)sharedManager;
- (BOOL)captureMenuProcessSnapshotIfAvailable;
- (void)relaunchMenuProcessIfSnapshotAvailable;

@end
