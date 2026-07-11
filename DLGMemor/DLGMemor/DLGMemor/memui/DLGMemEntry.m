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
static dispatch_source_t gPinnedRefreshTimer = nil;

+ (void)installOnActiveScene {
    if (gDLGMem != nil) return;
    gDLGMem = [[DLGMem alloc] init];
    [gDLGMem launchDLGMem];
    [DLGMemEntry startPinnedRefreshTimer];
}

// Periodically re-read every pinned address from the host
// process's memory and push the new chain to the UI. Fires every
// 1.0s on a low-priority background queue; the UI hop is done by
// DLGMem itself on the main queue.
+ (void)startPinnedRefreshTimer {
    if (gPinnedRefreshTimer != nil) return;
    gPinnedRefreshTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                  0, 0,
                                                  dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
    dispatch_source_set_timer(gPinnedRefreshTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                              (uint64_t)(1.0 * NSEC_PER_SEC),
                              (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gPinnedRefreshTimer, ^{
        if (gDLGMem != nil) {
            [gDLGMem refreshPinned];
        }
    });
    dispatch_resume(gPinnedRefreshTimer);
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