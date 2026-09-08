#import "ContactsChangeHistoryShim.h"

@implementation TTContactHistory
- (instancetype)initWithEvents:(NSArray<CNChangeHistoryEvent *> *)events token:(NSData *)token {
    self = [super init];
    if (self) {
        _events = [events copy];
        _token = [token copy];
    }
    return self;
}
@end

TTContactHistory *TTReadContactHistory(
    CNContactStore *store, CNChangeHistoryFetchRequest *request, NSError **error) {
    @try {
        CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *result =
            [store enumeratorForChangeHistoryFetchRequest:request error:error];
        if (!result) { return nil; }
        NSArray<CNChangeHistoryEvent *> *events = result.value.allObjects;
        return [[TTContactHistory alloc] initWithEvents:events token:result.currentHistoryToken];
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:CNErrorDomain code:CNErrorCodeCommunicationError
                                    userInfo:@{NSLocalizedDescriptionKey:
                                        @"Contacts history could not be read completely. It will be retried."}];
        }
        return nil;
    }
}
