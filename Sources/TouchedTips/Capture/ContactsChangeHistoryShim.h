@import Contacts;

NS_ASSUME_NONNULL_BEGIN

/// `-[CNContactStore enumeratorForChangeHistoryFetchRequest:error:]` is marked unavailable in Swift.
/// This is the same call, reachable from Swift through the bridging header.
CNFetchResult<NSEnumerator<CNChangeHistoryEvent *> *> *_Nullable TTChangeHistoryEnumerator(
    CNContactStore *store, CNChangeHistoryFetchRequest *request, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
