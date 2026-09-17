#import <UIKit/UIKit.h>
#import "QDCore.h"

static void (*originalSend)(id, SEL, unsigned int, id);
static __weak UIAlertController *activePicker;

static UIViewController *QDPresenter(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow || window.hidden) {
                continue;
            }
            UIViewController *controller = window.rootViewController;
            while (controller) {
                if (controller.presentedViewController &&
                    !controller.presentedViewController.isBeingDismissed) {
                    controller = controller.presentedViewController;
                } else if ([controller isKindOfClass:UINavigationController.class]) {
                    controller = ((UINavigationController *)controller).visibleViewController;
                } else if ([controller isKindOfClass:UITabBarController.class]) {
                    controller = ((UITabBarController *)controller).selectedViewController;
                } else {
                    return controller;
                }
            }
        }
    }
    return nil;
}

static void QDChooseResult(id sender, SEL selector, unsigned int sid, id context) {
    NSCAssert(NSThread.isMainThread, @"Picker must run on main thread");
    if (activePicker && !activePicker.isBeingDismissed) {
        return;
    }
    UIViewController *presenter = QDPresenter();
    if (!presenter || !presenter.view.window || presenter.isBeingDismissed ||
        presenter.isBeingPresented || [presenter isKindOfClass:UIAlertController.class]) {
        NSLog(@"[QQtouzi] Picker unavailable; dice send cancelled");
        return;
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"\u9ab0\u5b50\u70b9\u6570"
                         message:nil preferredStyle:UIAlertControllerStyleAlert];
    activePicker = alert;
    for (NSUInteger result = 1; result <= 6; result++) {
        NSString *title = [NSString stringWithFormat:@"%lu \u70b9", (unsigned long)result];
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
            handler:^(__unused UIAlertAction *action) {
                activePicker = nil;
                NSUInteger changed = QDWithResult(result, ^{
                    originalSend(sender, selector, sid, context);
                });
                NSLog(@"[QQtouzi] Requested=%lu patchedElements=%lu",
                      (unsigned long)result, (unsigned long)changed);
                if (changed != 1) {
                    NSLog(@"[QQtouzi] WARNING: send path differs from analyzed build");
                }
            }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"\u53d6\u6d88"
        style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) {
            activePicker = nil;
        }]];
    // Blocks retain the original sender and chat context until choice/cancel.
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void QDSend(id self, SEL selector, unsigned int sid, id context) {
    if (sid != 358 || !context) {
        originalSend(self, selector, sid, context);
        return;
    }
    if (NSThread.isMainThread) {
        QDChooseResult(self, selector, sid, context);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            QDChooseResult(self, selector, sid, context);
        });
    }
}

static void QDInstall(NSUInteger attempt) {
    static BOOL installed;
    if (installed) {
        return;
    }
    Class sender = NSClassFromString(@"NTFaceSendHandler");
    Class element = NSClassFromString(@"OCMsgElement");
    Class face = NSClassFromString(@"OCFaceElement");
    if (!sender || !element || !face) {
        if (attempt < 30) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{ QDInstall(attempt + 1); });
        } else {
            NSLog(@"[QQtouzi] Required QQ classes missing; hooks disabled");
        }
        return;
    }
    SEL selector = NSSelectorFromString(@"sendSuperEmojiWithSid:context:");
    if (!QDMethodMatches(sender, selector, "v", @[@"I", @"@"]) ||
        !QDInstallElementHook(element, face)) {
        NSLog(@"[QQtouzi] Method signature mismatch; hooks disabled");
        return;
    }
    Method method = class_getInstanceMethod(sender, selector);
    originalSend = (void (*)(id, SEL, unsigned int, id))method_getImplementation(method);
    if (!class_addMethod(sender, selector, (IMP)QDSend, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)QDSend);
    }
    installed = YES;
    NSLog(@"[QQtouzi] 0.1.0 loaded; QQ 9.3.65.605; ARM64");
}

__attribute__((constructor)) static void QDStart(void) {
    @autoreleasepool {
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        if (![info[@"CFBundleShortVersionString"] isEqualToString:@"9.3.65"] ||
            ![info[@"CFBundleVersion"] isEqualToString:@"9.3.65.605"]) {
            NSLog(@"[QQtouzi] Unsupported QQ version %@ (%@); hooks disabled",
                  info[@"CFBundleShortVersionString"], info[@"CFBundleVersion"]);
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ QDInstall(0); });
    }
}
