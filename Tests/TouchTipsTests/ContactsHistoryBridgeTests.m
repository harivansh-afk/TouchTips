@import XCTest;
#import "../../Sources/TouchTips/Capture/ContactsChangeHistoryShim.h"

@interface FailingHistoryEnumerator : NSEnumerator
@property(nonatomic) BOOL emittedFirst;
@end

@implementation FailingHistoryEnumerator
- (id)nextObject {
    if (!self.emittedFirst) {
        self.emittedFirst = YES;
        return [NSObject new];
    }
    [NSException raise:NSInternalInconsistencyException format:@"Injected mid-enumeration failure"];
    return nil;
}
@end

// CNFetchResult has no public initializer. Supply its two read-only selectors at the ObjC boundary.
@interface HistoryResultFixture : NSObject
@property(nonatomic, strong) NSEnumerator *value;
@property(nonatomic, copy) NSData *currentHistoryToken;
@end
@implementation HistoryResultFixture
@end

@interface HistoryStoreFixture : CNContactStore
@end
@implementation HistoryStoreFixture
- (CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *)enumeratorForChangeHistoryFetchRequest:
    (CNChangeHistoryFetchRequest *)request error:(NSError **)error {
    HistoryResultFixture *result = [HistoryResultFixture new];
    result.value = [FailingHistoryEnumerator new];
    result.currentHistoryToken = [@"uncommitted-token" dataUsingEncoding:NSUTF8StringEncoding];
    return (id)result;
}
@end

@interface ContactsHistoryBridgeTests : XCTestCase
@end
@implementation ContactsHistoryBridgeTests
- (void)testEnumerationFailureReturnsNeitherPartialEventsNorToken {
    NSError *error = nil;
    TTContactHistory *result = TTReadContactHistory([HistoryStoreFixture new], [CNChangeHistoryFetchRequest new], &error);
    XCTAssertNil(result);
    XCTAssertEqualObjects(error.domain, CNErrorDomain);
    XCTAssertEqual(error.code, CNErrorCodeCommunicationError);
}
@end
