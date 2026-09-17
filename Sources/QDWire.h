#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSData *QDRewriteDicePacket(NSData *packet, Class readerClass);
BOOL QDInstallWireHook(Class requestClass, Class readerClass);

NS_ASSUME_NONNULL_END
