#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A Safari content-blocker rule list, the JSON WebKit compiles from filter lists,
/// interpreted for Chromium views: requests it blocks are cancelled and elements it
/// hides get a stylesheet. A list is compiled once and shared by every view that
/// applies it; compiling a large list takes a while, so do it off the main thread.
@interface NFChromiumContentRuleList : NSObject

/// The list for `identifier`, reusing the compiled one while any view holds it.
/// `loadJSON` runs only when the list has to be compiled; nil when it returns no JSON
/// or JSON that is not a rule list.
+ (nullable instancetype)ruleListWithIdentifier:(NSString *)identifier
                                       loadJSON:(NSString *_Nullable (^)(void))loadJSON;

- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSString *identifier;
/// Rules in use; rules with actions or triggers Chromium can't apply are left out.
@property (nonatomic, readonly) NSUInteger ruleCount;

/// Whether the list blocks a load of `url`, of a Safari resource type such as "script"
/// or "document", by a page at `pageURL`, decided as a view decides it. For tests and
/// diagnostics.
- (BOOL)blocksURL:(NSURL *)url
     resourceType:(NSString *)resourceType
          pageURL:(NSURL *)pageURL NS_SWIFT_NAME(blocks(_:resourceType:pageURL:));

/// The stylesheet a view adds to a page at `pageURL`; empty when the list hides nothing
/// there.
- (NSString *)hidingStyleSheetForPageURL:(NSURL *)pageURL;

@end

NS_ASSUME_NONNULL_END
