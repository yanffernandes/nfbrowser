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

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
