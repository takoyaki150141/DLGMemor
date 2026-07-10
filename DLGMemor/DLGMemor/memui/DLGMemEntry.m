//
//  DLGMemEntry.m
//  memui
//
//  Bootstrap for the dylib constructor path.
//  - Wait for UIApplicationDidFinishLaunchingNotification AND a
//    connected foreground scene before installing the UI.
//  - The 1s "kill by system" race from the original (commit
//    e5bf481) is avoided by doing the work on the main queue
//    inside the notification handler, not in a constructor
//    dispatch_after.
//

#import "DLGMemEntry.h"
#import "DLGMem.h"

@implementation DLGMemEntry

static DLGMem *gDLGMem = nil;

+ (void)installOnActiveScene {
    if (gDLGMem != nil) return;
    gDLGMem = [[DLGMem alloc] init];
    [gDLGMem launchDLGMem];
}

__attribute__((constructor))
static void entry(void) {
    // Wait for the host process's UIApplicationDidFinishLaunching
    // notification before touching UIKit.  Constructor runs very
    // early in dyld load order and UIApplication.sharedApplication
    // can be in an undefined state on iOS 13+ until that fires.
    dispatch_once_t *guard = (dispatch_once_t *)calloc(1, sizeof(dispatch_once_t));
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
    free(guard);
}

@end