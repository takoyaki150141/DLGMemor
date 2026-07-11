//
//  DLGMemUI.m
//  memui
//
//  iOS 13+ scene-aware keyWindow lookup, plus a dedicated UIWindow
//  for the console panel so it doesn't ride on the host app's
//  keyWindow (and therefore doesn't get clipped by the host's
//  window-level ordering, or interfere with the host's responder
//  chain).
//
//  Changes vs original DeviLeo:
//    - scene-aware keyWindow lookup
//    - bounded 30s retry timer
//    - nil-handling
//    - gConsoleWindow: dedicated UIWindow at UIWindowLevelAlert+100
//      with a transparent rootViewController (required on iOS 26+)
//

#import "DLGMemUI.h"
#import "DLGMemUIView.h"
#import <UIKit/UIKit.h>

@implementation DLGMemUI

// Dedicated window for the console.  We keep a strong reference so
// the dylib's autorelease pool doesn't reclaim it on the next runloop.
static UIWindow *gConsoleWindow = nil;

#pragma mark - Scene-aware key window lookup

+ (UIWindow *)activeKeyWindow {
    __block UIWindow *result = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) {
                if (w.isKeyWindow) { result = w; break; }
            }
            if (result == nil && ws.windows.count > 0) {
                result = ws.windows.firstObject;
            }
            if (result != nil) break;
        }
    }

    if (result == nil) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        result = UIApplication.sharedApplication.keyWindow;
#pragma clang diagnostic pop
    }
    return result;
}

+ (void)addDLGMemUIView:(id<DLGMemUIViewDelegate>)delegate {
    // If the console is already up, just rebind the delegate.
    if (gConsoleWindow != nil) {
        DLGMemUIView *existing = [DLGMemUIView instance];
        if (existing != nil) existing.delegate = delegate;
        return;
    }

    UIWindow *hostWindow = [self activeKeyWindow];
    if (hostWindow == nil) {
        // Same retry pattern as before; pass nil to indicate "no host yet"
        // and create the console once any host window becomes available.
        __block int attempts = 0;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                         0, 0,
                                                         dispatch_get_main_queue());
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                  (uint64_t)(0.5 * NSEC_PER_SEC),
                                  (uint64_t)(0.05 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(timer, ^{
            UIWindow *w = [self activeKeyWindow];
            if (w != nil) {
                dispatch_source_cancel(timer);
                [self addDLGMemUIViewToHostWindow:w withDelegate:delegate];
                return;
            }
            if (++attempts >= 60) {
                dispatch_source_cancel(timer);
                NSLog(@"[DLGMemor] no foreground key window after 30s; UI not installed");
            }
        });
        dispatch_resume(timer);
        return;
    }

    [self addDLGMemUIViewToHostWindow:hostWindow withDelegate:delegate];
}

+ (void)addDLGMemUIViewToHostWindow:(UIWindow *)window withDelegate:(id<DLGMemUIViewDelegate>)delegate {
    if (window == nil) return;
    if (gConsoleWindow != nil) {
        // Already installed.
        DLGMemUIView *existing = [DLGMemUIView instance];
        if (existing != nil) existing.delegate = delegate;
        return;
    }

    CGRect screen = [UIScreen mainScreen].bounds;
    gConsoleWindow = [[UIWindow alloc] initWithFrame:screen];
    gConsoleWindow.windowLevel = UIWindowLevelAlert + 100;
    gConsoleWindow.backgroundColor = [UIColor clearColor];
    gConsoleWindow.userInteractionEnabled = YES;
    // Make the console non-key so it never steals key-window status
    // from the host app (which would break its responder chain).
    gConsoleWindow.hidden = YES;  // re-show once rootViewController is set

    // iOS 26 requires every UIWindow to have a rootViewController.
    UIViewController *rootVC = [[UIViewController alloc] init];
    rootVC.view.backgroundColor = [UIColor clearColor];
    rootVC.view.userInteractionEnabled = YES;
    gConsoleWindow.rootViewController = rootVC;

    // The console view sits in the root view controller's view.  The
    // existing layout code expects to be parented on a full-screen
    // view, so this is a drop-in.
    DLGMemUIView *view = [DLGMemUIView instance];
    view.delegate = delegate;
    view.translatesAutoresizingMaskIntoConstraints = YES;
    view.autoresizingMask = UIViewAutoresizingNone;
    // Place the floating console button ~25% from the left edge and
    // ~40% down the screen — far enough from the corner that it's
    // easy to tap, close enough to the thumb-reach zone on phones.
    CGFloat x = CGRectGetWidth(screen) * 0.25;
    CGFloat y = CGRectGetHeight(screen) * 0.40;
    view.frame = CGRectMake(x, y, DLG_DEBUG_CONSOLE_VIEW_SIZE, DLG_DEBUG_CONSOLE_VIEW_SIZE);
    view.alpha = 0.5f;
    [rootVC.view addSubview:view];

    // Pin the DLGMemUIView on the host window so the UIWindow+DLGMemUI
    // category methods (pan/toggle) can find it from their handleGesture:/
    // handleTTTapGesture: actions.  The category uses associated objects
    // and doesn't care which window the view is actually in.
    [window setDLGMemUIView:view];

    // Attach gestures.  Target is the host window because the
    // UIWindow+DLGMemUI category methods are added on UIWindow.
    NSArray *gestures = view.gestureRecognizers;
    if (gestures == nil || gestures.count == 0) {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:window action:@selector(handleGesture:)];
        [view addGestureRecognizer:pan];

        UITapGestureRecognizer *tttap = [[UITapGestureRecognizer alloc] initWithTarget:window action:@selector(handleTTTapGesture:)];
        tttap.numberOfTapsRequired = 3;
        tttap.numberOfTouchesRequired = 3;
        [view addGestureRecognizer:tttap];
    }

    // Now make the window visible.  iOS won't honor a UIWindow that's
    // both non-key and hidden, but it WILL honor one that has a
    // rootViewController and `hidden = NO` even without being the
    // keyWindow.
    gConsoleWindow.hidden = NO;

    if ([delegate respondsToSelector:@selector(DLGMemUILaunched:)]) {
        [delegate DLGMemUILaunched:view];
    }
}

+ (void)removeDLGMemUIView {
    DLGMemUIView *view = [DLGMemUIView instance];
    if (view == nil) return;
    if (view.expanded) [view doCollapse];

    NSArray *gestures = view.gestureRecognizers;
    for (UIGestureRecognizer *gesture in gestures) {
        [view removeGestureRecognizer:gesture];
    }
    [view removeFromSuperview];

    if (gConsoleWindow != nil) {
        // Detach the root view controller so the window can be
        // released safely.
        gConsoleWindow.rootViewController = nil;
        gConsoleWindow.hidden = YES;
        gConsoleWindow = nil;
    }
}

@end