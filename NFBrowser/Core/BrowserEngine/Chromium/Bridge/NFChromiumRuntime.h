#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFChromiumCookiePolicy) {
    NFChromiumCookiePolicyAllowAll,
    NFChromiumCookiePolicyBlockThirdParty,
    NFChromiumCookiePolicyBlockAll,
};

/// Owns the CEF browser-process lifecycle: lazy CefInitialize on first use, the
/// external message pump on the main run loop, per-profile request contexts and
/// an orderly CefShutdown. Main thread only.
@interface NFChromiumRuntime : NSObject

@property (class, nonatomic, readonly, strong) NFChromiumRuntime *shared;

@property (nonatomic, readonly) BOOL isRunning;
/// Full CEF version, e.g. "154.0.34+g14c5a08+chromium-154.0.8037.98".
@property (nonatomic, readonly, copy) NSString *cefVersion;
/// Chromium version, e.g. "154.0.8037.98".
@property (nonatomic, readonly, copy) NSString *chromiumVersion;
/// Directory that holds one Chromium profile per Space.
@property (nonatomic, readonly, strong) NSURL *rootCacheURL;
@property (nonatomic, readonly) NSInteger liveBrowserCount;

/// Loads the framework and calls CefInitialize the first time it is needed.
- (BOOL)startIfNeededWithError:(NSError *_Nullable *_Nullable)error;

/// Closes every browser, drains the pump and calls CefShutdown. No-op when not running.
- (void)shutdown;

/// Profile data operations start Chromium when needed; completions run on the main thread.

/// Adds cookies to a profile and reports how many Chromium accepted.
- (void)setCookies:(NSArray<NSHTTPCookie *> *)cookies
        forProfile:(NSString *)profileIdentifier
        persistent:(BOOL)persistent
        completion:(void (^)(NSInteger accepted))completion;

/// Deletes every cookie of a profile, or only those for `host` and its parent domains.
- (void)deleteCookiesForProfile:(NSString *)profileIdentifier
                     persistent:(BOOL)persistent
                           host:(nullable NSString *)host
                     completion:(void (^)(void))completion;

/// Applies a Space's cookie policy to its profile through Chromium's own settings.
- (void)setCookiePolicy:(NFChromiumCookiePolicy)policy
             forProfile:(NSString *)profileIdentifier
             persistent:(BOOL)persistent;

/// Clears a profile's HTTP cache.
- (void)clearCacheForProfile:(NSString *)profileIdentifier
                  persistent:(BOOL)persistent
                  completion:(void (^)(void))completion;

/// Drops an in-memory (private) profile so its cookies and storage are released.
- (void)discardEphemeralProfile:(NSString *)profileIdentifier;

/// Forgets a profile: its context is dropped now and its directory is deleted right
/// away, or before Chromium starts next time if the running engine may still use it.
- (void)removeProfile:(NSString *)profileIdentifier;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
