#import "QDCore.h"
#include <stdlib.h>
#include <string.h>

@protocol QDFace <NSObject>
- (unsigned int)faceIndex;
- (void)setResultId:(NSString *)value;
- (void)setRandomType:(NSNumber *)value;
@end

typedef struct QDSendScope {
    NSUInteger result;
    NSUInteger changed;
    struct QDSendScope *previous;
} QDSendScope;

// QQ builds the outgoing element synchronously. Never carry a choice into
// unrelated work, another thread, or a later incoming message.
static _Thread_local QDSendScope *activeScope;
static void (*originalSetFace)(id, SEL, id);
static Class expectedFaceClass;

BOOL QDMethodMatches(Class cls, SEL selector, const char *returnType,
                     NSArray<NSString *> *argumentTypes) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != argumentTypes.count + 2) {
        return NO;
    }
    char *type = method_copyReturnType(method);
    BOOL matches = type && strcmp(type, returnType) == 0;
    free(type);
    for (NSUInteger i = 0; matches && i < argumentTypes.count; i++) {
        type = method_copyArgumentType(method, (unsigned int)i + 2);
        matches = type && strcmp(type, argumentTypes[i].UTF8String) == 0;
        free(type);
    }
    return matches;
}

static void QDSetFace(id self, SEL selector, id face) {
    QDSendScope *scope = activeScope;
    if (scope && scope->changed == 0 && [face isKindOfClass:expectedFaceClass] &&
        [(id<QDFace>)face faceIndex] == 358) {
        [(id<QDFace>)face setResultId:[NSString stringWithFormat:@"%lu",
                                      (unsigned long)scope->result]];
        [(id<QDFace>)face setRandomType:@1];
        // Keep QQ's native sticker type for previews, history, and forwarding.
        scope->changed++;
    }
    originalSetFace(self, selector, face);
}

BOOL QDInstallElementHook(Class elementClass, Class faceClass) {
    if (originalSetFace) {
        return YES;
    }
    SEL setter = NSSelectorFromString(@"setFaceElement:");
    if (!QDMethodMatches(elementClass, setter, "v", @[@"@"]) ||
        !QDMethodMatches(faceClass, NSSelectorFromString(@"faceIndex"), "I", @[]) ||
        !QDMethodMatches(faceClass, NSSelectorFromString(@"setResultId:"), "v", @[@"@"]) ||
        !QDMethodMatches(faceClass, NSSelectorFromString(@"setRandomType:"), "v", @[@"@"])) {
        return NO;
    }
    Method method = class_getInstanceMethod(elementClass, setter);
    expectedFaceClass = faceClass;
    originalSetFace = (void (*)(id, SEL, id))method_getImplementation(method);
    // Add an override when the implementation belongs to a superclass.
    if (!class_addMethod(elementClass, setter, (IMP)QDSetFace, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)QDSetFace);
    }
    return YES;
}

NSUInteger QDWithResult(NSUInteger result, void (NS_NOESCAPE ^send)(void)) {
    if (result < 1 || result > 6 || !send) {
        return 0;
    }
    QDSendScope scope = {result, 0, activeScope};
    activeScope = &scope;
    @try {
        send();
    } @finally {
        activeScope = scope.previous;
    }
    return scope.changed;
}
