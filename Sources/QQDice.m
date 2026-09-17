#import <UIKit/UIKit.h>
#import "QDCore.h"
#import "QDWire.h"

static void (*originalSend)(id, SEL, unsigned int, id);
static void (*originalInteractiveSend)(id, SEL, id, unsigned int);
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

static void QDChooseResult(void (^send)(void)) {
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
                NSUInteger changed = QDWithResult(result, send);
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
    // The send block retains the original sender and contact until choice/cancel.
    [presenter presentViewController:alert animated:YES completion:nil];
}

static void QDQueuePicker(void (^send)(void)) {
    if (NSThread.isMainThread) {
        QDChooseResult(send);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            QDChooseResult(send);
        });
    }
}

static void QDSend(id self, SEL selector, unsigned int sid, id context) {
    if (sid != 358 || !context) {
        originalSend(self, selector, sid, context);
        return;
    }
    QDQueuePicker(^{ originalSend(self, selector, sid, context); });
}

static void QDInteractiveSend(id self, SEL selector, id contact, unsigned int sid) {
    if (sid != 358 || !contact) {
        originalInteractiveSend(self, selector, contact, sid);
        return;
    }
    QDQueuePicker(^{ originalInteractiveSend(self, selector, contact, sid); });
}

static IMP QDReplace(Class cls, SEL selector, IMP replacement) {
    Method method = class_getInstanceMethod(cls, selector);
    IMP original = method_getImplementation(method);
    if (!class_addMethod(cls, selector, replacement, method_getTypeEncoding(method))) {
        method_setImplementation(method, replacement);
    }
    return original;
}

static void QDInstall(NSUInteger attempt) {
    if (originalSend && originalInteractiveSend) {
        return;
    }
    Class sender = NSClassFromString(@"NTFaceSendHandler");
    Class interactive = NSClassFromString(@"FaceRichBoard.NTAIOFaceRichBoardViewModel");
    Class element = NSClassFromString(@"OCMsgElement");
    Class face = NSClassFromString(@"OCFaceElement");
    Class request = NSClassFromString(@"MSFReqModel");
    Class reader = NSClassFromString(@"GPBCodedInputStream");
    if (element && face && QDInstallWireHook(request, reader) && QDInstallElementHook(element, face)) {
        SEL selector = NSSelectorFromString(@"onSendLottieEmojiWithContact:emojiId:");
        if (!originalInteractiveSend &&
            QDMethodMatches(interactive, selector, "v", @[@"@", @"I"])) {
            originalInteractiveSend = (void (*)(id, SEL, id, unsigned int))
                QDReplace(interactive, selector, (IMP)QDInteractiveSend);
            NSLog(@"[QQtouzi] 0.4.0 interactive dice hook installed");
        }
        selector = NSSelectorFromString(@"sendSuperEmojiWithSid:context:");
        if (!originalSend && QDMethodMatches(sender, selector, "v", @[@"I", @"@"])) {
            originalSend = (void (*)(id, SEL, unsigned int, id))
                QDReplace(sender, selector, (IMP)QDSend);
            NSLog(@"[QQtouzi] Legacy super-emoji hook installed");
        }
    }
    if (!originalSend || !originalInteractiveSend) {
        if (attempt < 30) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{ QDInstall(attempt + 1); });
        } else {
            NSLog(@"[QQtouzi] Missing/incompatible send hooks: interactive=%d legacy=%d",
                  originalInteractiveSend != NULL, originalSend != NULL);
        }
    }
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
