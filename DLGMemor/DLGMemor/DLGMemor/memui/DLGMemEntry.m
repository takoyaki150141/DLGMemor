//
//  DLGMemEntry.m
//  memui
//
//  Bootstrap for the dylib constructor path.
//
//  DeviLeo's original fired `+launchDLGMem` from a 1-second
//  dispatch_after inside a `__attribute__((constructor))`. On iOS
//  13+ this raced UIApplicationDidFinishLaunching and the system
//  routinely killed the dylib before it could attach (the bug
//  commit e5bf481 tried to paper over).
//
//  New flow:
//    1. Constructor installs an observer for
//       UIApplicationDidFinishLaunchingNotification on the main queue.
//    2. The observer waits 0.1s for the foreground scene to become
//       active (covers iOS 13+ scene lifecycle), then installs.
//    3. Singleton guard so a second dylib load doesn't double-fire.
//

#import "DLGMemEntry.h"
#import "DLGMem.h"
#import <UIKit/UIKit.h>

@implementation DLGMemEntry

static DLGMem *gDLGMem = nil;

+ (void)installOnActiveScene {
    if (gDLGMem != nil) return;
    gDLGMem = [[DLGMem alloc] init];
    [gDLGMem launchDLGMem];
}

__attribute__((constructor))
static void entry(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            // Wait one runloop turn for the scene to activate on
            // scene-based apps; 0.1s is enough in practice and
            // keeps total boot time low.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [DLGMemEntry installOnActiveScene];
            });
        }];
    });
}

@end