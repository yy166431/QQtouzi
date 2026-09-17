#import <Foundation/Foundation.h>
#import "QDCore.h"

@interface MockFace : NSObject
@property(nonatomic) unsigned int faceIndex;
@property(nonatomic, copy) NSString *resultId;
@property(nonatomic, strong) NSNumber *randomType;
@property(nonatomic, strong) NSNumber *stickerType;
@end
@implementation MockFace
@end

@interface MockElementBase : NSObject
@property(nonatomic, strong) MockFace *faceElement;
@end
@implementation MockElementBase
@end

@interface MockElement : MockElementBase
@end
@implementation MockElement
@end

@interface WrongFace : NSObject
- (id)faceIndex;
@end
@implementation WrongFace
- (id)faceIndex { return @358; }
@end

static MockFace *Face(unsigned int sid) {
    MockFace *face = [MockFace new];
    face.faceIndex = sid;
    face.stickerType = @2;
    return face;
}

static MockFace *Attach(unsigned int sid) {
    MockFace *face = Face(sid);
    [MockElement new].faceElement = face;
    return face;
}

int main(void) {
    @autoreleasepool {
        NSCAssert(!QDInstallElementHook(MockElement.class, WrongFace.class), @"Reject wrong ABI");
        NSCAssert(QDInstallElementHook(MockElement.class, MockFace.class), @"Install hook");
        NSCAssert(QDInstallElementHook(MockElement.class, MockFace.class), @"Idempotent install");
        for (NSUInteger result = 1; result <= 6; result++) {
            __block MockFace *sent;
            NSUInteger changed = QDWithResult(result, ^{
                MockFace *other = Attach(359);
                NSCAssert(other.resultId == nil && [other.stickerType isEqual:@2], @"Other emoji unchanged");
                sent = Attach(358);
                MockFace *second = Attach(358);
                NSCAssert(second.resultId == nil && [second.stickerType isEqual:@2], @"Only one element per choice");
            });
            NSCAssert(changed == 1, @"Exactly one outgoing dice patched");
            NSCAssert(sent.resultId.integerValue == (NSInteger)result, @"Selected result survives return");
            NSCAssert([sent.randomType isEqual:@1], @"Interactive result type");
            NSCAssert([sent.stickerType isEqual:@2], @"Preserve native dice for preview and forwarding");
            MockFace *incoming = Attach(358);
            NSCAssert(incoming.resultId == nil && [incoming.stickerType isEqual:@2], @"Unscoped incoming message unchanged");
        }
        __block BOOL called = NO;
        NSCAssert(QDWithResult(0, ^{ called = YES; }) == 0, @"Reject zero");
        NSCAssert(QDWithResult(7, ^{ called = YES; }) == 0, @"Reject seven");
        NSCAssert(!called, @"Invalid input cannot send");
        QDWithResult(6, ^{
            QDWithResult(2, ^{
                NSCAssert([Attach(358).resultId isEqual:@"2"], @"Nested choice");
            });
            NSCAssert([Attach(358).resultId isEqual:@"6"], @"Restore outer choice");
        });
        QDWithResult(4, ^{
            MockFace *baseFace = Face(358);
            [MockElementBase new].faceElement = baseFace;
            NSCAssert(baseFace.resultId == nil, @"Superclass implementation not replaced");
            dispatch_semaphore_t completed = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                NSCAssert(Attach(358).resultId == nil, @"Other thread isolated");
                dispatch_semaphore_signal(completed);
            });
            NSCAssert(dispatch_semaphore_wait(completed,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0, @"Worker completed");
        });
        @try {
            QDWithResult(5, ^{
                @throw [NSException exceptionWithName:@"Test" reason:nil userInfo:nil];
            });
        } @catch (__unused NSException *exception) {
            NSCAssert(Attach(358).resultId == nil, @"Exception restores scope");
        }
        dispatch_apply(40, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t i) {
            @autoreleasepool {
                NSUInteger result = i % 6 + 1;
                QDWithResult(result, ^{
                    NSCAssert(Attach(358).resultId.integerValue == (NSInteger)result, @"Concurrent choices isolated");
                });
            }
        });
        NSLog(@"QQtouzi core tests passed");
    }
    return 0;
}
