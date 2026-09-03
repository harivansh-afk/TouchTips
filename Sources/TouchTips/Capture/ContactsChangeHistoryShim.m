#import "ContactsChangeHistoryShim.h"

CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *TTChangeHistoryEnumerator(
    CNContactStore *store, CNChangeHistoryFetchRequest *request, NSError **error) {
    return [store enumeratorForChangeHistoryFetchRequest:request error:error];
}
