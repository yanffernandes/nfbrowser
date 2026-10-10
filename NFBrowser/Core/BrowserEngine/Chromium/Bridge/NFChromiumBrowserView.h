#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFChromiumBrowserView;

typedef NS_ENUM(NSInteger, NFChromiumJavaScriptDialogType) {
    NFChromiumJavaScriptDialogTypeAlert,
    NFChromiumJavaScriptDialogTypeConfirm,
    NFChromiumJavaScriptDialogTypePrompt,
};

/// A download started by a Chromium page. Values refresh on every update callback.
@interface NFChromiumDownload : NSObject
@property (nonatomic, readonly) uint32_t identifier;
@property (nonatomic, readonly, nullable) NSURL *url;
@property (nonatomic, readonly, nullable) NSURL *originalURL;
@property (nonatomic, readonly, copy) NSString *suggestedFileName;
@property (nonatomic, readonly, copy) NSString *mimeType;
@property (nonatomic, readonly, nullable) NSURL *destinationURL;
@property (nonatomic, readonly) int64_t receivedBytes;
/// -1 when the server did not send a length.
@property (nonatomic, readonly) int64_t totalBytes;
@property (nonatomic, readonly) BOOL isInProgress;
@property (nonatomic, readonly) BOOL isComplete;
@property (nonatomic, readonly) BOOL isCanceled;
@property (nonatomic, readonly) BOOL isInterrupted;
- (void)cancel;
- (instancetype)init NS_UNAVAILABLE;
@end

@protocol NFChromiumBrowserViewDelegate <NSObject>
@optional
- (void)chromiumBrowserViewDidCreateBrowser:(NFChromiumBrowserView *)view;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didChangeAddress:(NSURL *)url;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didChangeTitle:(NSString *)title;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didChangeFaviconURLs:(NSArray<NSURL *> *)urls;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didChangeLoadingProgress:(double)progress;
/// isLoading, canGoBack and canGoForward were updated.
- (void)chromiumBrowserViewDidChangeLoadingState:(NFChromiumBrowserView *)view;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didStartNavigationToURL:(nullable NSURL *)url;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    didFinishNavigationToURL:(nullable NSURL *)url
              httpStatusCode:(NSInteger)httpStatusCode;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    didFailNavigationToURL:(nullable NSURL *)url
                 errorCode:(NSInteger)errorCode
                 errorText:(NSString *)errorText;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view didRequestFullscreen:(BOOL)fullscreen;
/// Chromium wanted to open a popup or new tab. The popup itself is cancelled;
/// the receiver decides where to open the URL.
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    didRequestNewTabWithURL:(NSURL *)url
                userGesture:(BOOL)userGesture
               inBackground:(BOOL)inBackground;
- (void)chromiumBrowserViewDidClose:(NFChromiumBrowserView *)view;
/// DevTools protocol events, e.g. "Runtime.bindingCalled".
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    didReceiveDevToolsEvent:(NSString *)method
                     params:(NSDictionary<NSString *, id> *)params;
/// Call the completion with a file URL to save the download there, or nil to cancel it.
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    decideDestinationForDownload:(NFChromiumDownload *)download
                      completion:(void (^)(NSURL *_Nullable destination))completion;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view downloadDidUpdate:(NFChromiumDownload *)download;
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    requestMediaAccessForOrigin:(nullable NSURL *)origin
                          video:(BOOL)video
                          audio:(BOOL)audio
                       decision:(void (^)(BOOL granted))decision;
/// alert/confirm/prompt. Called asynchronously, outside Chromium's message loop; call
/// the completion exactly once. Without this method Chromium shows its own dialogs.
- (void)chromiumBrowserView:(NFChromiumBrowserView *)view
    runJavaScriptDialogOfType:(NFChromiumJavaScriptDialogType)type
                      message:(NSString *)message
            defaultPromptText:(NSString *)defaultPromptText
                   completion:(void (^)(BOOL accepted, NSString *_Nullable userInput))completion;
@end

/// Hosts one Chromium browser (CEF, Alloy style) as a child view. The browser is
/// created on the first load or DevTools call, or when the view joins a window.
@interface NFChromiumBrowserView : NSView

/// `profileIdentifier` names the Chromium profile (one per Space). Persistent profiles
/// keep cookies and storage on disk; ephemeral ones are discarded with the session.
- (instancetype)initWithFrame:(NSRect)frame
            profileIdentifier:(NSString *)profileIdentifier
                   persistent:(BOOL)persistent
                   initialURL:(nullable NSURL *)initialURL NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithFrame:(NSRect)frame NS_UNAVAILABLE;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<NFChromiumBrowserViewDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *profileIdentifier;
@property (nonatomic, readonly) BOOL isPersistentProfile;
@property (nonatomic, readonly) BOOL hasBrowser;
@property (nonatomic, readonly, nullable) NSURL *currentURL;
@property (nonatomic, readonly, copy, nullable) NSString *title;
@property (nonatomic, readonly) BOOL isLoading;
@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;
/// 0...1
@property (nonatomic, readonly) double loadingProgress;
/// Chromium zoom level: 0 is 100%, each step is a factor of 1.2.
@property (nonatomic) double zoomLevel;
/// Hosts whose certificate errors the user chose to accept.
@property (nonatomic, copy) NSSet<NSString *> *allowedInsecureHosts;
/// Hosts blocked when a page loads them as a third party (tracker protection);
/// subdomains of a listed host are blocked too.
@property (nonatomic, copy) NSSet<NSString *> *blockedThirdPartyHosts;
/// DevTools events forwarded to the delegate; nil forwards all of them.
@property (nonatomic, copy, nullable) NSSet<NSString *> *observedDevToolsEvents;

- (void)loadURL:(NSURL *)url;
- (void)reload;
- (void)reloadIgnoringCache;
- (void)stopLoading;
- (void)goBack;
- (void)goForward;
- (void)focusBrowser;
/// Tells Chromium the view was hidden or shown so it can throttle rendering.
- (void)setBrowserHidden:(BOOL)hidden;

/// Evaluates in the main frame through the DevTools protocol (Runtime.evaluate,
/// promises awaited). The result is a JSON-compatible value or nil.
- (void)evaluateJavaScript:(NSString *)script
                completion:(nullable void (^)(id _Nullable result, NSError *_Nullable error))completion;
- (void)captureScreenshotWithCompletion:(void (^)(NSImage *_Nullable image, NSError *_Nullable error))completion;
/// Sends any DevTools protocol method; no DevTools window is needed.
- (void)sendDevToolsMethod:(NSString *)method
                    params:(nullable NSDictionary<NSString *, id> *)params
                completion:(nullable void (^)(NSDictionary<NSString *, id> *_Nullable result,
                                              NSError *_Nullable error))completion;

- (void)findString:(NSString *)string forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext;
- (void)stopFindingAndClearSelection:(BOOL)clearSelection;
- (void)printPage;
- (void)showDevTools;
/// Closes the browser; the delegate gets chromiumBrowserViewDidClose when Chromium is done.
- (void)closeBrowser;

@end

NS_ASSUME_NONNULL_END
