#import <Foundation/Foundation.h>
#import <GPBCodedInputStream.h>
#import <GPBCodedOutputStream.h>
#import "QDWire.h"

@interface MockRequestBase : NSObject
@property(nonatomic, copy) NSString *cmd;
@property(nonatomic, strong) NSData *data;
@end
@implementation MockRequestBase
@end
@interface MockRequest : MockRequestBase
@end
@implementation MockRequest
@end

static NSData *Encode(void (^write)(GPBCodedOutputStream *)) {
    NSOutputStream *stream = [NSOutputStream outputStreamToMemory];
    [stream open];
    GPBCodedOutputStream *output = [[GPBCodedOutputStream alloc] initWithOutputStream:stream];
    write(output);
    [output flush];
    NSData *data = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    [stream close];
    return data;
}

static NSData *Dice(NSString *result, uint32_t face, uint32_t type, uint32_t random) {
    return Encode(^(GPBCodedOutputStream *output) {
        [output writeString:1 value:@"1"];
        [output writeString:2 value:@"33"];
        [output writeUInt32:3 value:face];
        [output writeUInt32:4 value:1];
        [output writeUInt32:5 value:type];
        if (result) [output writeString:6 value:result];
        [output writeString:7 value:@"/dice"];
        [output writeUInt32:9 value:random];
        [output writeBytes:50 value:[NSData dataWithBytes:"\x18\x02" length:2]];
    });
}

static NSData *Element(NSData *dice, uint32_t service, uint32_t business, BOOL duplicate) {
    NSData *common = Encode(^(GPBCodedOutputStream *output) {
        [output writeUInt32:1 value:service];
        [output writeBytes:2 value:dice];
        [output writeUInt32:3 value:business];
        if (duplicate) [output writeUInt32:3 value:business];
    });
    return Encode(^(GPBCodedOutputStream *output) { [output writeBytes:53 value:common]; });
}

static NSData *Frame(NSData *payload) {
    uint32_t length = (uint32_t)payload.length + 4;
    const uint8_t prefix[] = {length >> 24, length >> 16, length >> 8, length};
    NSMutableData *data = [NSMutableData dataWithBytes:prefix length:4];
    [data appendData:payload];
    return data;
}

static NSData *Packet(NSArray<NSData *> *elements) {
    NSData *rich = Encode(^(GPBCodedOutputStream *output) {
        [output writeFixed32:60 value:0xdeadbeef];
        for (NSData *element in elements) [output writeBytes:2 value:element];
        [output writeFixed64:61 value:UINT64_MAX];
    });
    NSData *body = Encode(^(GPBCodedOutputStream *output) { [output writeBytes:1 value:rich]; });
    return Frame(Encode(^(GPBCodedOutputStream *output) {
        [output writeUInt32:4 value:42];
        [output writeBytes:3 value:body];
        [output writeBytes:70 value:[@"unrelated content" dataUsingEncoding:NSUTF8StringEncoding]];
    }));
}

static NSData *SelectedPacket(NSString *result, uint32_t business) {
    return Packet(@[Element(Dice(result, 358, 2, 1), 37, business, NO)]);
}

static void Unchanged(NSData *data) {
    NSCAssert(QDRewriteDicePacket(data, GPBCodedInputStream.class) == data, @"Pass through unsupported data");
}

int main(void) {
    @autoreleasepool {
        for (NSUInteger result = 1; result <= 6; result++) {
            NSString *digit = [NSString stringWithFormat:@"%lu", (unsigned long)result];
            NSData *before = SelectedPacket(digit, 2);
            NSData *after = QDRewriteDicePacket(before, GPBCodedInputStream.class);
            NSCAssert([after isEqualToData:SelectedPacket(digit, 0)], @"Only outer business changes");
            NSCAssert(before.length == after.length, @"Framing and lengths preserved");
            NSUInteger changed = 0;
            for (NSUInteger i = 0; i < before.length; i++) {
                changed += ((const uint8_t *)before.bytes)[i] != ((const uint8_t *)after.bytes)[i];
            }
            NSCAssert(changed == 1, @"Unknown fields and dice fields preserved byte for byte");
            Unchanged(after);
        }
        // QQ clears resultId when forwarding a native dice. Such sends must reroll.
        Unchanged(Packet(@[Element(Dice(nil, 358, 2, 0), 37, 2, NO)]));
        Unchanged(Packet(@[Element(Dice(@"", 358, 2, 1), 37, 2, NO)]));
        Unchanged(Packet(@[Element(Dice(@"6", 358, 2, 0), 37, 2, NO)]));
        Unchanged(Packet(@[Element(Dice(@"6", 359, 2, 1), 37, 2, NO)]));
        Unchanged(Packet(@[Element(Dice(@"6", 358, 0, 1), 37, 0, NO)]));
        Unchanged(Packet(@[Element(Dice(@"6", 358, 2, 1), 23, 2, NO)]));
        Unchanged(Packet(@[Element(Dice(@"6", 358, 2, 1), 37, 2, YES)]));
        for (NSString *digit in @[@"0", @"7", @"06", @"-1", @"random"]) Unchanged(SelectedPacket(digit, 2));
        NSData *selected = Element(Dice(@"6", 358, 2, 1), 37, 2, NO);
        Unchanged(Packet(@[selected, selected]));
        NSData *text = Encode(^(GPBCodedOutputStream *output) { [output writeString:1 value:@"hello"]; });
        NSCAssert([QDRewriteDicePacket(Packet(@[text, selected]), GPBCodedInputStream.class)
                   isEqualToData:Packet(@[text, Element(Dice(@"6", 358, 2, 1), 37, 0, NO)])],
                  @"Other elements remain untouched");
        NSMutableData *duplicateDice = [Dice(@"6", 358, 2, 1) mutableCopy];
        [duplicateDice appendData:Encode(^(GPBCodedOutputStream *output) { [output writeUInt32:3 value:358]; })];
        Unchanged(Packet(@[Element(duplicateDice, 37, 2, NO)]));

        NSData *valid = SelectedPacket(@"6", 2);
        for (NSUInteger length = 0; length < valid.length; length++) {
            Unchanged([valid subdataWithRange:NSMakeRange(0, length)]);
        }
        NSData *payload = [valid subdataWithRange:NSMakeRange(4, valid.length - 4)];
        for (NSUInteger length = 0; length < payload.length; length++) {
            // Valid truncations at field boundaries may still contain a full dice;
            // malformed truncations must never throw or produce an invalid frame.
            NSData *cut = Frame([payload subdataWithRange:NSMakeRange(0, length)]);
            NSData *output = QDRewriteDicePacket(cut, GPBCodedInputStream.class);
            NSCAssert(output.length == cut.length, @"Truncated packets handled without resizing");
        }
        uint8_t invalid[] = {0, 0, 0, 6, 0x1a, 0xff};
        Unchanged([NSData dataWithBytes:invalid length:sizeof(invalid)]);
        Unchanged(Frame([NSData dataWithBytes:"\x1b" length:1]));
        Unchanged([NSMutableData dataWithLength:65537]);
        NSCAssert(QDRewriteDicePacket(valid, NSObject.class) == valid, @"Unavailable parser is harmless");

        NSCAssert(!QDInstallWireHook(MockRequest.class, NSObject.class), @"Reject incompatible parser");
        NSCAssert(QDInstallWireHook(MockRequest.class, GPBCodedInputStream.class), @"Install request hook");
        NSCAssert(QDInstallWireHook(MockRequest.class, GPBCodedInputStream.class), @"Idempotent install");
        MockRequestBase *base = [MockRequestBase new];
        base.cmd = @"MessageSvc.PbSendMsg";
        base.data = valid;
        NSCAssert(base.data == valid, @"Superclass is not hooked");
        MockRequest *request = [MockRequest new];
        request.cmd = @"Unrelated.Service";
        request.data = valid;
        NSCAssert(request.data == valid, @"Other commands are unchanged");
        request.cmd = @"MessageSvc.PbSendMsg";
        NSData *first = request.data;
        NSCAssert([first isEqualToData:SelectedPacket(@"6", 0)], @"Request is rewritten");
        NSCAssert(request.data == first, @"Repeated reads reuse cached output");
        request.data = SelectedPacket(@"2", 2);
        NSCAssert([request.data isEqualToData:SelectedPacket(@"2", 0)], @"Changed input invalidates cache");
        NSMutableData *mutable = [valid mutableCopy];
        request.data = mutable;
        NSCAssert([request.data isEqualToData:first], @"Mutable input supported");
        ((uint8_t *)mutable.mutableBytes)[0] = 1;
        NSCAssert(request.data == mutable, @"In-place changes cannot return stale output");
        request.data = valid;
        dispatch_apply(32, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(__unused size_t i) {
            @autoreleasepool {
                NSCAssert([request.data isEqualToData:first], @"Concurrent reads are stable");
            }
        });
        NSLog(@"QQtouzi wire tests passed");
    }
    return 0;
}
