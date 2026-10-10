#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

/// Clears a profile's HTTP cache.
- (void)clearCacheForProfile:(NSString *)profileIdentifier
                  persistent:(BOOL)persistent
                  completion:(void (^)(void))completion;

/// Forgets a profile: its context is dropped now and its directory is deleted right
/// away, or before Chromium starts next time if the running engine may still use it.
- (void)removeProfile:(NSString *)profileIdentifier;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
