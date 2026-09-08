@import Contacts;

NS_ASSUME_NONNULL_BEGIN

/// A fully consumed batch. Contacts can raise an Objective-C exception during enumeration;
/// neither partial events nor their new cursor may escape to Swift on failure.
@interface TTContactHistory : NSObject
@property(nonatomic, readonly) NSArray<CNChangeHistoryEvent *> *events;
@property(nonatomic, readonly) NSData *token;
@end

TTContactHistory *_Nullable TTReadContactHistory(
    CNContactStore *store, CNChangeHistoryFetchRequest *request, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
