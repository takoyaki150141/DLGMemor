//
//  DLGMemUI.m
//  memui
//
//  Updated for iOS 13+ scene lifecycle (DeviLeo original kept for history
//  of the public repo; keyWindow-only lookup was the source of the
//  "rendering sometimes fails" bug).
//
//  Changes vs original:
//    - scene-aware keyWindow lookup that walks connectedScenes first
//      and only falls back to UIApplication.keyWindow on legacy hosts
//    - bounded 30s retry timer instead of infinite recursive delay
//    - nil-handling on every API call so we never crash on a window
//      that's mid-destruction
//

#import "DLGMemUI.h"
#import "DLGMemUIView.h"
#import <UIKit/UIKit.h>

@implementation DLGMemUI

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
    UIWindow *window = [self activeKeyWindow];
    if (window != nil) {
        [self addDLGMemUIViewToWindow:window withDelegate:delegate];
        return;
    }

    // No foreground window yet — poll for one with a hard 30s cap
    // so we don't leak a timer forever if the scene never activates.
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
            [self addDLGMemUIViewToWindow:w withDelegate:delegate];
            return;
        }
        if (++attempts >= 60) {
            dispatch_source_cancel(timer);
            NSLog(@"[DLGMemor] no foreground key window after 30s; UI not installed");
        }
    });
    dispatch_resume(timer);
}

+ (void)addDLGMemUIViewToWindow:(UIWindow *)window withDelegate:(id<DLGMemUIViewDelegate>)delegate{
    if (window == nil) return;

    CGRect frame = CGRectMake(0, 100, DLG_DEBUG_CONSOLE_VIEW_SIZE, DLG_DEBUG_CONSOLE_VIEW_SIZE);
    DLGMemUIView *view = [DLGMemUIView instance];
    view.delegate = delegate;
    view.translatesAutoresizingMaskIntoConstraints = YES;
    view.autoresizingMask = UIViewAutoresizingNone;
    view.frame = frame;
    view.alpha = 0.5f;
    [window addSubview:view];
    [window setDLGMemUIView:view];

    NSArray *gestures = view.gestureRecognizers;
    if (gestures == nil || gestures.count == 0) {
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:window action:@selector(handleGesture:)];
        [view addGestureRecognizer:pan];

        UITapGestureRecognizer *tttap = [[UITapGestureRecognizer alloc] initWithTarget:window action:@selector(handleTTTapGesture:)];
        tttap.numberOfTapsRequired = 3;
        tttap.numberOfTouchesRequired = 3;
        [window addGestureRecognizer:tttap];
    }

    if ([delegate respondsToSelector:@selector(DLGMemUILaunched:)]) {
        [delegate DLGMemUILaunched:view];
    }
}

+ (void)removeDLGMemUIView {
    DLGMemUIView *view = [DLGMemUIView instance];
    if (view.expanded) [view doCollapse];
    NSArray *gestures = view.gestureRecognizers;
    for (UIGestureRecognizer *gesture in gestures) {
        [view removeGestureRecognizer:gesture];
    }
    [view removeFromSuperview];
}

@end