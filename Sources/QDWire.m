#import "QDWire.h"
#import "QDCore.h"

@protocol QDProtoReader <NSObject>
- (instancetype)initWithData:(NSData *)data;
- (BOOL)isAtEnd;
- (int32_t)readTag;
- (uint64_t)readUInt64;
- (NSData *)readBytes;
- (NSUInteger)position;
- (BOOL)skipField:(int32_t)tag;
@end

@protocol QDRequest <NSObject>
- (NSString *)cmd;
@end

@interface QDProtoField : NSObject
@property(nonatomic) uint32_t number;
@property(nonatomic) uint32_t wire;
@property(nonatomic) uint64_t integer;
@property(nonatomic) NSRange range;
@property(nonatomic, strong) NSData *bytes;
@end
@implementation QDProtoField
@end

// Use QQ's protobuf reader; retain byte ranges so unknown fields and field order
// remain exactly as QQ encoded them. Only a one-byte business value is replaced.
static NSArray<QDProtoField *> *QDFields(NSData *data, NSUInteger offset, Class readerClass) {
    id<QDProtoReader> reader = [[readerClass alloc] initWithData:data];
    if (!reader) return nil;
    NSMutableArray<QDProtoField *> *fields = [NSMutableArray array];
    while (![reader isAtEnd]) {
        if (fields.count >= 4096) return nil;
        int32_t tag = [reader readTag];
        QDProtoField *field = [QDProtoField new];
        field.number = (uint32_t)tag >> 3;
        field.wire = (uint32_t)tag & 7;
        if (field.number == 0) return nil;
        NSUInteger start = [reader position];
        if (field.wire == 0) {
            field.integer = [reader readUInt64];
        } else if (field.wire == 2) {
            field.bytes = [reader readBytes];
            if (!field.bytes || field.bytes.length > [reader position]) return nil;
            start = [reader position] - field.bytes.length;
        } else if (field.wire == 1 || field.wire == 5) {
            if (![reader skipField:tag]) return nil;
        } else {
            return nil;
        }
        NSUInteger end = [reader position];
        if (end < start || end > data.length) return nil;
        field.range = NSMakeRange(offset + start, end - start);
        [fields addObject:field];
    }
    return fields;
}

static QDProtoField *QDOnly(NSArray<QDProtoField *> *fields, uint32_t number, uint32_t wire) {
    QDProtoField *found = nil;
    for (QDProtoField *field in fields) {
        if (field.number != number) continue;
        if (found || field.wire != wire) return nil;
        found = field;
    }
    return found;
}

static BOOL QDInteger(NSArray<QDProtoField *> *fields, uint32_t number, uint64_t value) {
    QDProtoField *field = QDOnly(fields, number, 0);
    return field && field.integer == value;
}

static BOOL QDString(NSArray<QDProtoField *> *fields, uint32_t number, NSString *value) {
    QDProtoField *field = QDOnly(fields, number, 2);
    return field && [field.bytes isEqualToData:[value dataUsingEncoding:NSUTF8StringEncoding]];
}

static NSArray<QDProtoField *> *QDChildren(QDProtoField *field, Class readerClass) {
    return field ? QDFields(field.bytes, field.range.location, readerClass) : nil;
}

NSData *QDRewriteDicePacket(NSData *packet, Class readerClass) {
    if (![packet isKindOfClass:NSData.class] || packet.length < 4 ||
        packet.length > 65536 || !readerClass) return packet;
    const uint8_t *bytes = packet.bytes;
    uint32_t length = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) |
                      ((uint32_t)bytes[2] << 8) | bytes[3];
    if (length != packet.length) return packet;
    @try {
        NSArray *root = QDFields([packet subdataWithRange:NSMakeRange(4, length - 4)], 4, readerClass);
        NSArray *body = QDChildren(QDOnly(root, 3, 2), readerClass);
        NSArray *rich = QDChildren(QDOnly(body, 1, 2), readerClass);
        if (!rich) return packet;
        QDProtoField *replacement = nil;
        for (QDProtoField *element in rich) {
            if (element.number != 2) continue;
            if (element.wire != 2) return packet;
            NSArray *fields = QDChildren(element, readerClass);
            if (!fields) return packet;
            NSUInteger commonCount = 0;
            for (QDProtoField *field in fields) commonCount += field.number == 53;
            if (commonCount == 0) continue;
            if (commonCount != 1) return packet;
            NSArray *common = QDChildren(QDOnly(fields, 53, 2), readerClass);
            if (!common) return packet;
            if (!QDInteger(common, 1, 37)) continue;
            QDProtoField *business = QDOnly(common, 3, 0);
            if (!business || business.integer != 2 || business.range.length != 1) continue;
            NSArray *dice = QDChildren(QDOnly(common, 2, 2), readerClass);
            if (!dice) return packet;
            QDProtoField *result = QDOnly(dice, 6, 2);
            if (!QDInteger(dice, 3, 358) || !QDInteger(dice, 4, 1) ||
                !QDInteger(dice, 5, 2) || !QDInteger(dice, 9, 1) ||
                !QDString(dice, 1, @"1") || !QDString(dice, 2, @"33") ||
                !result || result.bytes.length != 1) continue;
            uint8_t digit = ((const uint8_t *)result.bytes.bytes)[0];
            if (digit < '1' || digit > '6') continue;
            if (replacement) return packet;
            replacement = business;
        }
        if (!replacement) return packet;
        NSMutableData *output = [packet mutableCopy];
        ((uint8_t *)output.mutableBytes)[replacement.range.location] = 0;
        return [output copy];
    } @catch (__unused NSException *exception) {
        return packet;
    }
}

static NSData *(*originalData)(id, SEL);
static Class protobufReader;
static char cacheKey;

static NSData *QDRequestData(id self, SEL selector) {
    NSData *data = originalData(self, selector);
    if (!data || ![[(id<QDRequest>)self cmd] isEqualToString:@"MessageSvc.PbSendMsg"]) return data;
    @synchronized (self) {
        NSArray<NSData *> *cache = objc_getAssociatedObject(self, &cacheKey);
        if (cache && [cache[0] isEqualToData:data]) return cache[1];
        NSData *output = QDRewriteDicePacket(data, protobufReader);
        if (output != data) {
            objc_setAssociatedObject(self, &cacheKey, @[[data copy], output], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        } else if (cache) {
            objc_setAssociatedObject(self, &cacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return output;
    }
}

BOOL QDInstallWireHook(Class requestClass, Class readerClass) {
    if (originalData) return YES;
    if (!QDMethodMatches(requestClass, @selector(data), "@", @[]) ||
        !QDMethodMatches(requestClass, @selector(cmd), "@", @[]) ||
        !QDMethodMatches(readerClass, @selector(initWithData:), "@", @[@"@"]) ||
        !QDMethodMatches(readerClass, @selector(isAtEnd), @encode(BOOL), @[]) ||
        !QDMethodMatches(readerClass, @selector(readTag), @encode(int32_t), @[]) ||
        !QDMethodMatches(readerClass, @selector(readUInt64), @encode(uint64_t), @[]) ||
        !QDMethodMatches(readerClass, @selector(readBytes), "@", @[]) ||
        !QDMethodMatches(readerClass, @selector(position), @encode(NSUInteger), @[]) ||
        !QDMethodMatches(readerClass, @selector(skipField:), @encode(BOOL), @[@(@encode(int32_t))])) return NO;
    Method method = class_getInstanceMethod(requestClass, @selector(data));
    protobufReader = readerClass;
    originalData = (NSData *(*)(id, SEL))method_getImplementation(method);
    if (!class_addMethod(requestClass, @selector(data), (IMP)QDRequestData, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)QDRequestData);
    }
    return YES;
}
