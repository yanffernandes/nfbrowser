// Objective-C++ only: not part of the Swift bridging header.
#import "NFChromiumRuntime.h"

#include "include/cef_browser.h"
#include "include/cef_request_context.h"

NS_ASSUME_NONNULL_BEGIN

@interface NFChromiumRuntime (Internal)

/// Runs `block` once CEF has finished initializing its global context (immediately
/// if it already has). Browsers must not be created before that point.
- (void)performWhenContextReady:(dispatch_block_t)block;

/// Persistent profiles live in `rootCacheURL/<identifier>`; ephemeral ones stay in
/// memory and are shared by every browser that asks for the same identifier.
- (CefRefPtr<CefRequestContext>)requestContextForProfile:(NSString *)identifier persistent:(BOOL)persistent;

/// Drops the in-memory profile so its cookies and storage are discarded.
- (void)discardEphemeralProfile:(NSString *)identifier;

- (void)browserDidCreate:(CefRefPtr<CefBrowser>)browser;
- (void)browserDidClose:(CefRefPtr<CefBrowser>)browser;

@end

NS_ASSUME_NONNULL_END
