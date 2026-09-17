#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

BOOL QDMethodMatches(Class cls, SEL selector, const char *returnType,
                     NSArray<NSString *> *argumentTypes);
BOOL QDInstallElementHook(Class elementClass, Class faceClass);
NSUInteger QDWithResult(NSUInteger result, void (NS_NOESCAPE ^send)(void));

NS_ASSUME_NONNULL_END

