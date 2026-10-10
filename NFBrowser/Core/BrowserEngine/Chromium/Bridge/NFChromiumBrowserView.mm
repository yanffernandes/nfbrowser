#import "NFChromiumBrowserView.h"

#include <string>
#include <vector>

#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_parser.h"

#import "NFChromiumRuntime+Internal.h"

static NSString *const NFChromiumBrowserErrorDomain = @"NFChromiumBrowserView";

static NSString *NSStringFromCefString(const CefString &value) {
    std::string utf8 = value.ToString();
    return [[NSString alloc] initWithBytes:utf8.data() length:utf8.size() encoding:NSUTF8StringEncoding] ?: @"";
}

static NSURL *_Nullable NSURLFromCefString(const CefString &value) {
    NSString *string = NSStringFromCefString(value);
    return string.length > 0 ? [NSURL URLWithString:string] : nil;
}

static NSError *NFChromiumError(NSInteger code, NSString *description) {
    return [NSError errorWithDomain:NFChromiumBrowserErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static id _Nullable NFJSONObject(NSData *data) {
    return data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

static NSDictionary *NFDictionary(id _Nullable object) {
    return [object isKindOfClass:NSDictionary.class] ? object : @{};
}

#pragma mark - NFChromiumDownload

@interface NFChromiumDownload ()
@property (nonatomic, copy, nullable) void (^cancelHandler)(void);
@property (nonatomic) BOOL cancelRequested;
- (instancetype)initWithIdentifier:(uint32_t)identifier;
- (void)updateWithItem:(CefRefPtr<CefDownloadItem>)item;
@end

@implementation NFChromiumDownload

- (instancetype)initWithIdentifier:(uint32_t)identifier {
    if ((self = [super init])) {
        _identifier = identifier;
        _suggestedFileName = @"";
        _mimeType = @"";
        _totalBytes = -1;
    }
    return self;
}

- (void)updateWithItem:(CefRefPtr<CefDownloadItem>)item {
    _url = NSURLFromCefString(item->GetURL());
    _originalURL = NSURLFromCefString(item->GetOriginalUrl());
    NSString *suggested = NSStringFromCefString(item->GetSuggestedFileName());
    if (suggested.length > 0) {
        _suggestedFileName = suggested;
    }
    _mimeType = NSStringFromCefString(item->GetMimeType());
    NSString *fullPath = NSStringFromCefString(item->GetFullPath());
    if (fullPath.length > 0) {
        _destinationURL = [NSURL fileURLWithPath:fullPath];
    }
    _receivedBytes = item->GetReceivedBytes();
    _totalBytes = item->GetTotalBytes() > 0 ? item->GetTotalBytes() : -1;
    _isInProgress = item->IsInProgress();
    _isComplete = item->IsComplete();
    _isCanceled = item->IsCanceled();
    _isInterrupted = item->IsInterrupted();
}

- (void)cancel {
    self.cancelRequested = YES;
    if (self.cancelHandler) {
        self.cancelHandler();
    }
}

@end

#pragma mark - Callbacks from the CEF client

@interface NFChromiumBrowserView ()
@property (nonatomic, readwrite, nullable) NSURL *currentURL;
@property (nonatomic, readwrite, copy, nullable) NSString *title;
@property (nonatomic, readwrite) BOOL isLoading;
@property (nonatomic, readwrite) BOOL canGoBack;
@property (nonatomic, readwrite) BOOL canGoForward;
@property (nonatomic, readwrite) double loadingProgress;

- (void)nf_addressChanged:(nullable NSURL *)url;
- (void)nf_titleChanged:(NSString *)title;
- (void)nf_faviconURLsChanged:(NSArray<NSURL *> *)urls;
- (void)nf_fullscreenChanged:(BOOL)fullscreen;
- (void)nf_progressChanged:(double)progress;
- (void)nf_loadingStateChangedLoading:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward;
- (void)nf_loadStarted:(nullable NSURL *)url;
- (void)nf_loadEnded:(nullable NSURL *)url httpStatusCode:(int)httpStatusCode;
- (void)nf_loadFailed:(nullable NSURL *)url errorCode:(int)errorCode errorText:(NSString *)errorText;
- (void)nf_requestNewTabWithURL:(NSURL *)url userGesture:(BOOL)userGesture inBackground:(BOOL)inBackground;
- (void)nf_browserCreated:(CefRefPtr<CefBrowser>)browser;
- (void)nf_browserDidClose;
- (BOOL)nf_beforeDownload:(CefRefPtr<CefDownloadItem>)item
            suggestedName:(NSString *)suggestedName
                 callback:(CefRefPtr<CefBeforeDownloadCallback>)callback;
- (void)nf_downloadUpdated:(CefRefPtr<CefDownloadItem>)item callback:(CefRefPtr<CefDownloadItemCallback>)callback;
- (BOOL)nf_requestMediaAccessForOrigin:(nullable NSURL *)origin
                           permissions:(uint32_t)permissions
                              callback:(CefRefPtr<CefMediaAccessCallback>)callback;
- (void)nf_devToolsResult:(int)messageId success:(BOOL)success data:(NSData *)data;
- (void)nf_devToolsEvent:(NSString *)method data:(NSData *)data;
- (BOOL)nf_runJavaScriptDialog:(NFChromiumJavaScriptDialogType)type
                       message:(NSString *)message
             defaultPromptText:(NSString *)defaultPromptText
                      callback:(CefRefPtr<CefJSDialogCallback>)callback;
@end

namespace {

// window.open() popups that ask for a window (OAuth and payment sign-in flows) need
// window.opener, so Chromium hosts them in its own native window. They get this
// separate client so their events never reach the opener tab's view.
class NFChromiumPopupClient : public CefClient, public CefLifeSpanHandler, public CefDisplayHandler {
   public:
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        [NFChromiumRuntime.shared browserDidCreate:browser];
    }

    // OnBeforeClose does not reliably arrive for native popup windows, so the
    // runtime lets go of the browser as soon as closing starts.
    bool DoClose(CefRefPtr<CefBrowser> browser) override {
        [NFChromiumRuntime.shared browserDidClose:browser];
        return false;
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        [NFChromiumRuntime.shared browserDidClose:browser];
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
        view.window.title = NSStringFromCefString(title);
    }

   private:
    IMPLEMENT_REFCOUNTING(NFChromiumPopupClient);
};

// All callbacks arrive on the CEF UI thread, which is the main thread on macOS.
class NFChromiumClient : public CefClient,
                         public CefLifeSpanHandler,
                         public CefLoadHandler,
                         public CefDisplayHandler,
                         public CefDownloadHandler,
                         public CefPermissionHandler,
                         public CefRequestHandler,
                         public CefJSDialogHandler,
                         public CefKeyboardHandler,
                         public CefDevToolsMessageObserver {
   public:
    explicit NFChromiumClient(NFChromiumBrowserView *view) : view_(view) {}

    void Detach() { view_ = nil; }

    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
    CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }
    CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }

    // CefLifeSpanHandler

    bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       int popup_id,
                       const CefString &target_url,
                       const CefString &target_frame_name,
                       WindowOpenDisposition target_disposition,
                       bool user_gesture,
                       const CefPopupFeatures &popupFeatures,
                       CefWindowInfo &windowInfo,
                       CefRefPtr<CefClient> &client,
                       CefBrowserSettings &settings,
                       CefRefPtr<CefDictionaryValue> &extra_info,
                       bool *no_javascript_access) override {
        if (target_disposition == CEF_WOD_NEW_POPUP && user_gesture) {
            client = new NFChromiumPopupClient();
            return false;
        }
        NSURL *url = NSURLFromCefString(target_url);
        if (url) {
            BOOL background = target_disposition == CEF_WOD_NEW_BACKGROUND_TAB;
            [view_ nf_requestNewTabWithURL:url userGesture:user_gesture inBackground:background];
        }
        return true;
    }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
        [NFChromiumRuntime.shared browserDidCreate:browser];
        NFChromiumBrowserView *view = view_;
        if (view) {
            [view nf_browserCreated:browser];
        } else {
            browser->GetHost()->CloseBrowser(true);
        }
    }

    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
        [NFChromiumRuntime.shared browserDidClose:browser];
        [view_ nf_browserDidClose];
    }

    // CefDisplayHandler

    void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, const CefString &url) override {
        if (frame->IsMain()) {
            [view_ nf_addressChanged:NSURLFromCefString(url)];
        }
    }

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override {
        [view_ nf_titleChanged:NSStringFromCefString(title)];
    }

    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString> &icon_urls) override {
        NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:icon_urls.size()];
        for (const CefString &iconURL : icon_urls) {
            NSURL *url = NSURLFromCefString(iconURL);
            if (url) {
                [urls addObject:url];
            }
        }
        [view_ nf_faviconURLsChanged:urls];
    }

    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override {
        [view_ nf_fullscreenChanged:fullscreen];
    }

    void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override {
        [view_ nf_progressChanged:progress];
    }

    // CefLoadHandler

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override {
        [view_ nf_loadingStateChangedLoading:isLoading canGoBack:canGoBack canGoForward:canGoForward];
    }

    void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, TransitionType transition_type) override {
        if (frame->IsMain()) {
            [view_ nf_loadStarted:NSURLFromCefString(frame->GetURL())];
        }
    }

    void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame, int httpStatusCode) override {
        if (frame->IsMain()) {
            [view_ nf_loadEnded:NSURLFromCefString(frame->GetURL()) httpStatusCode:httpStatusCode];
        }
    }

    void OnLoadError(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     ErrorCode errorCode,
                     const CefString &errorText,
                     const CefString &failedUrl) override {
        if (!frame->IsMain() || errorCode == ERR_ABORTED) {
            return;
        }
        [view_ nf_loadFailed:NSURLFromCefString(failedUrl)
                   errorCode:errorCode
                   errorText:NSStringFromCefString(errorText)];
    }

    // CefDownloadHandler

    bool CanDownload(CefRefPtr<CefBrowser> browser, const CefString &url, const CefString &request_method) override {
        return true;
    }

    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString &suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override {
        NFChromiumBrowserView *view = view_;
        if (!view) {
            return false;
        }
        return [view nf_beforeDownload:download_item
                         suggestedName:NSStringFromCefString(suggested_name)
                              callback:callback];
    }

    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) override {
        [view_ nf_downloadUpdated:download_item callback:callback];
    }

    // CefPermissionHandler

    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                        CefRefPtr<CefFrame> frame,
                                        const CefString &requesting_origin,
                                        uint32_t requested_permissions,
                                        CefRefPtr<CefMediaAccessCallback> callback) override {
        NFChromiumBrowserView *view = view_;
        if (!view) {
            return false;
        }
        return [view nf_requestMediaAccessForOrigin:NSURLFromCefString(requesting_origin)
                                        permissions:requested_permissions
                                           callback:callback];
    }

    // CefRequestHandler

    bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                            cef_errorcode_t cert_error,
                            const CefString &request_url,
                            CefRefPtr<CefSSLInfo> ssl_info,
                            CefRefPtr<CefCallback> callback) override {
        NSString *host = NSURLFromCefString(request_url).host;
        if (host && [view_.allowedInsecureHosts containsObject:host]) {
            callback->Continue();
            return true;
        }
        return false;
    }

    // CefJSDialogHandler

    bool OnJSDialog(CefRefPtr<CefBrowser> browser,
                    const CefString &origin_url,
                    JSDialogType dialog_type,
                    const CefString &message_text,
                    const CefString &default_prompt_text,
                    CefRefPtr<CefJSDialogCallback> callback,
                    bool &suppress_message) override {
        NFChromiumJavaScriptDialogType type = NFChromiumJavaScriptDialogTypeAlert;
        if (dialog_type == JSDIALOGTYPE_CONFIRM) {
            type = NFChromiumJavaScriptDialogTypeConfirm;
        } else if (dialog_type == JSDIALOGTYPE_PROMPT) {
            type = NFChromiumJavaScriptDialogTypePrompt;
        }
        return [view_ nf_runJavaScriptDialog:type
                                     message:NSStringFromCefString(message_text)
                           defaultPromptText:NSStringFromCefString(default_prompt_text)
                                    callback:callback];
    }

    // CefKeyboardHandler

    // Command shortcuts the page did not consume go to the app menu (Cmd+L, Cmd+T, ...).
    bool OnKeyEvent(CefRefPtr<CefBrowser> browser, const CefKeyEvent &event, CefEventHandle os_event) override {
        if (event.type != KEYEVENT_RAWKEYDOWN || !(event.modifiers & EVENTFLAG_COMMAND_DOWN) || !os_event) {
            return false;
        }
        return [NSApp.mainMenu performKeyEquivalent:(__bridge NSEvent *)os_event];
    }

    // CefDevToolsMessageObserver

    void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,
                                int message_id,
                                bool success,
                                const void *result,
                                size_t result_size) override {
        NSData *data = result_size > 0 ? [NSData dataWithBytes:result length:result_size] : [NSData data];
        [view_ nf_devToolsResult:message_id success:success data:data];
    }

    void OnDevToolsEvent(CefRefPtr<CefBrowser> browser,
                         const CefString &method,
                         const void *params,
                         size_t params_size) override {
        NSData *data = params_size > 0 ? [NSData dataWithBytes:params length:params_size] : [NSData data];
        [view_ nf_devToolsEvent:NSStringFromCefString(method) data:data];
    }

   private:
    __weak NFChromiumBrowserView *view_;
    IMPLEMENT_REFCOUNTING(NFChromiumClient);
};

}  // namespace

#pragma mark - NFChromiumBrowserView

typedef void (^NFDevToolsCompletion)(NSDictionary<NSString *, id> *_Nullable, NSError *_Nullable);

@implementation NFChromiumBrowserView {
    CefRefPtr<NFChromiumClient> _client;
    CefRefPtr<CefBrowser> _browser;
    CefRefPtr<CefRegistration> _devToolsRegistration;
    NSURL *_pendingURL;
    NSMutableArray<dispatch_block_t> *_pendingActions;
    NSMutableDictionary<NSNumber *, NFDevToolsCompletion> *_devToolsCompletions;
    NSMutableDictionary<NSNumber *, NFChromiumDownload *> *_downloads;
    double _pendingZoomLevel;
    BOOL _isCreatingBrowser;
    BOOL _closeRequested;
}

- (instancetype)initWithFrame:(NSRect)frame
            profileIdentifier:(NSString *)profileIdentifier
                   persistent:(BOOL)persistent
                   initialURL:(NSURL *)initialURL {
    if ((self = [super initWithFrame:frame])) {
        _profileIdentifier = [profileIdentifier copy];
        _isPersistentProfile = persistent;
        _pendingURL = initialURL;
        _pendingActions = [NSMutableArray array];
        _devToolsCompletions = [NSMutableDictionary dictionary];
        _downloads = [NSMutableDictionary dictionary];
        _allowedInsecureHosts = [NSSet set];
    }
    return self;
}

- (void)dealloc {
    if (_client) {
        _client->Detach();
    }
    if (_browser) {
        _browser->GetHost()->CloseBrowser(true);
    }
}

- (BOOL)hasBrowser {
    return _browser != nullptr;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window != nil) {
        [self ensureBrowser];
    }
}

// CEF creates the child browser only under a view that is already in a window;
// earlier loads and DevTools calls wait in the queue until then.
- (void)ensureBrowser {
    if (self.window != nil && !_browser && !_isCreatingBrowser && !_closeRequested) {
        [self createBrowser];
    }
}

- (void)createBrowser {
    NSError *error = nil;
    if (![NFChromiumRuntime.shared startIfNeededWithError:&error]) {
        NSLog(@"[NFChromium] %@", error.localizedDescription);
        [self nf_loadFailed:_pendingURL errorCode:-1 errorText:error.localizedDescription];
        return;
    }
    _isCreatingBrowser = YES;
    __weak NFChromiumBrowserView *weakSelf = self;
    [NFChromiumRuntime.shared performWhenContextReady:^{
      [weakSelf createBrowserWhenContextReady];
    }];
}

// Creation is asynchronous: CEF waits for the profile to initialize and then
// delivers the browser through OnAfterCreated.
- (void)createBrowserWhenContextReady {
    if (_closeRequested) {
        _isCreatingBrowser = NO;
        return;
    }
    CefWindowInfo windowInfo;
    NSRect bounds = self.bounds;
    windowInfo.SetAsChild((__bridge CefWindowHandle)self,
                          CefRect(0, 0, (int)NSWidth(bounds), (int)NSHeight(bounds)));
    CefBrowserSettings browserSettings;
    CefRefPtr<CefRequestContext> context =
        [NFChromiumRuntime.shared requestContextForProfile:_profileIdentifier persistent:_isPersistentProfile];
    std::string url = _pendingURL.absoluteString.UTF8String ?: "";
    _pendingURL = nil;
    _client = new NFChromiumClient(self);
    if (!CefBrowserHost::CreateBrowser(windowInfo, _client, url, browserSettings, nullptr, context)) {
        _isCreatingBrowser = NO;
        [self nf_loadFailed:nil errorCode:-1 errorText:@"Chromium could not create the browser."];
    }
}

- (void)nf_browserCreated:(CefRefPtr<CefBrowser>)browser {
    _isCreatingBrowser = NO;
    _browser = browser;
    if (_closeRequested) {
        browser->GetHost()->CloseBrowser(true);
        return;
    }

    _devToolsRegistration = browser->GetHost()->AddDevToolsMessageObserver(_client);
    NSView *browserView = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    browserView.frame = self.bounds;
    browserView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (_pendingURL) {
        browser->GetMainFrame()->LoadURL(_pendingURL.absoluteString.UTF8String);
        _pendingURL = nil;
    }
    if (_pendingZoomLevel != 0) {
        browser->GetHost()->SetZoomLevel(_pendingZoomLevel);
    }

    NSArray<dispatch_block_t> *actions = [_pendingActions copy];
    [_pendingActions removeAllObjects];
    for (dispatch_block_t action in actions) {
        action();
    }
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserViewDidCreateBrowser:)]) {
        [self.delegate chromiumBrowserViewDidCreateBrowser:self];
    }
}

#pragma mark Navigation

- (void)loadURL:(NSURL *)url {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self loadURL:url];
        });
        return;
    }
    if (!_browser) {
        _pendingURL = url;
        [self ensureBrowser];
        return;
    }
    _browser->GetMainFrame()->LoadURL(url.absoluteString.UTF8String);
}

- (void)reload {
    if (_browser) {
        _browser->Reload();
    }
}

- (void)reloadIgnoringCache {
    if (_browser) {
        _browser->ReloadIgnoreCache();
    }
}

- (void)stopLoading {
    if (_browser) {
        _browser->StopLoad();
    }
}

- (void)goBack {
    if (_browser && _browser->CanGoBack()) {
        _browser->GoBack();
    }
}

- (void)goForward {
    if (_browser && _browser->CanGoForward()) {
        _browser->GoForward();
    }
}

- (void)focusBrowser {
    if (_browser) {
        _browser->GetHost()->SetFocus(true);
    }
}

- (void)setBrowserHidden:(BOOL)hidden {
    if (_browser) {
        NSView *browserView = (__bridge NSView *)_browser->GetHost()->GetWindowHandle();
        browserView.hidden = hidden;
    }
}

- (double)zoomLevel {
    return _browser ? _browser->GetHost()->GetZoomLevel() : _pendingZoomLevel;
}

- (void)setZoomLevel:(double)zoomLevel {
    if (_browser) {
        _browser->GetHost()->SetZoomLevel(zoomLevel);
    } else {
        _pendingZoomLevel = zoomLevel;
    }
}

#pragma mark DevTools protocol

- (void)sendDevToolsMethod:(NSString *)method
                    params:(NSDictionary<NSString *, id> *)params
                completion:(NFDevToolsCompletion)completion {
    // CEF only accepts DevTools calls on its UI thread, which is the main thread.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self sendDevToolsMethod:method params:params completion:completion];
        });
        return;
    }
    if (!_browser) {
        if (_closeRequested) {
            if (completion) {
                completion(nil, NFChromiumError(1, @"The browser is closed."));
            }
            return;
        }
        __weak NFChromiumBrowserView *weakSelf = self;
        [_pendingActions addObject:^{
          [weakSelf sendDevToolsMethod:method params:params completion:completion];
        }];
        [self ensureBrowser];
        return;
    }

    CefRefPtr<CefDictionaryValue> dictionary;
    if (params.count > 0) {
        NSData *json = [NSJSONSerialization isValidJSONObject:params]
                           ? [NSJSONSerialization dataWithJSONObject:params options:0 error:nil]
                           : nil;
        CefRefPtr<CefValue> value =
            json ? CefParseJSON(std::string((const char *)json.bytes, json.length), JSON_PARSER_RFC) : nullptr;
        if (!value || value->GetType() != VTYPE_DICTIONARY) {
            if (completion) {
                completion(nil, NFChromiumError(2, @"DevTools parameters are not valid JSON."));
            }
            return;
        }
        dictionary = value->GetDictionary();
    }

    int messageId = _browser->GetHost()->ExecuteDevToolsMethod(0, method.UTF8String, dictionary);
    if (messageId == 0) {
        if (completion) {
            completion(nil, NFChromiumError(3, [NSString stringWithFormat:@"Could not send %@.", method]));
        }
        return;
    }
    if (completion) {
        _devToolsCompletions[@(messageId)] = [completion copy];
    }
}

- (void)evaluateJavaScript:(NSString *)script completion:(void (^)(id, NSError *))completion {
    NSDictionary *params = @{@"expression": script, @"returnByValue": @YES, @"awaitPromise": @YES, @"userGesture": @YES};
    [self sendDevToolsMethod:@"Runtime.evaluate"
                      params:params
                  completion:^(NSDictionary *result, NSError *error) {
                    if (!completion) {
                        return;
                    }
                    if (error) {
                        completion(nil, error);
                        return;
                    }
                    NSDictionary *exceptionDetails = NFDictionary(result[@"exceptionDetails"]);
                    if (exceptionDetails.count > 0) {
                        NSString *message = NFDictionary(exceptionDetails[@"exception"])[@"description"];
                        if (![message isKindOfClass:NSString.class]) {
                            message = exceptionDetails[@"text"];
                        }
                        completion(nil, NFChromiumError(4, [message isKindOfClass:NSString.class]
                                                               ? message
                                                               : @"JavaScript exception"));
                        return;
                    }
                    id value = NFDictionary(result[@"result"])[@"value"];
                    completion(value == NSNull.null ? nil : value, nil);
                  }];
}

- (void)captureScreenshotWithCompletion:(void (^)(NSImage *, NSError *))completion {
    [self sendDevToolsMethod:@"Page.captureScreenshot"
                      params:@{@"format": @"png"}
                  completion:^(NSDictionary *result, NSError *error) {
                    NSString *base64 = result[@"data"];
                    NSData *png = [base64 isKindOfClass:NSString.class]
                                      ? [[NSData alloc] initWithBase64EncodedString:base64 options:0]
                                      : nil;
                    NSImage *image = png ? [[NSImage alloc] initWithData:png] : nil;
                    completion(image, image ? nil : (error ?: NFChromiumError(5, @"No screenshot data.")));
                  }];
}

- (void)nf_devToolsResult:(int)messageId success:(BOOL)success data:(NSData *)data {
    NFDevToolsCompletion completion = _devToolsCompletions[@(messageId)];
    if (!completion) {
        return;
    }
    [_devToolsCompletions removeObjectForKey:@(messageId)];
    NSDictionary *payload = NFDictionary(NFJSONObject(data));
    if (success) {
        completion(payload, nil);
        return;
    }
    NSString *message = [payload[@"message"] isKindOfClass:NSString.class] ? payload[@"message"]
                                                                           : @"DevTools method failed.";
    completion(nil, [NSError errorWithDomain:NFChromiumBrowserErrorDomain
                                        code:[payload[@"code"] integerValue]
                                    userInfo:@{NSLocalizedDescriptionKey: message}]);
}

- (void)nf_devToolsEvent:(NSString *)method data:(NSData *)data {
    if (self.observedDevToolsEvents && ![self.observedDevToolsEvents containsObject:method]) {
        return;
    }
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didReceiveDevToolsEvent:params:)]) {
        [self.delegate chromiumBrowserView:self didReceiveDevToolsEvent:method params:NFDictionary(NFJSONObject(data))];
    }
}

#pragma mark Page tools

- (void)findString:(NSString *)string forward:(BOOL)forward matchCase:(BOOL)matchCase findNext:(BOOL)findNext {
    if (_browser && string.length > 0) {
        _browser->GetHost()->Find(string.UTF8String, forward, matchCase, findNext);
    }
}

- (void)stopFindingAndClearSelection:(BOOL)clearSelection {
    if (_browser) {
        _browser->GetHost()->StopFinding(clearSelection);
    }
}

- (void)printPage {
    if (_browser) {
        _browser->GetHost()->Print();
    }
}

- (void)showDevTools {
    if (_browser) {
        CefWindowInfo windowInfo;
        CefBrowserSettings settings;
        _browser->GetHost()->ShowDevTools(windowInfo, nullptr, settings, CefPoint());
    }
}

- (void)closeBrowser {
    _closeRequested = YES;
    if (_browser) {
        _browser->GetHost()->CloseBrowser(true);
    }
}

#pragma mark Client callbacks

- (void)nf_addressChanged:(NSURL *)url {
    self.currentURL = url;
    if (url && [self.delegate respondsToSelector:@selector(chromiumBrowserView:didChangeAddress:)]) {
        [self.delegate chromiumBrowserView:self didChangeAddress:url];
    }
}

- (void)nf_titleChanged:(NSString *)title {
    self.title = title;
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didChangeTitle:)]) {
        [self.delegate chromiumBrowserView:self didChangeTitle:title];
    }
}

- (void)nf_faviconURLsChanged:(NSArray<NSURL *> *)urls {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didChangeFaviconURLs:)]) {
        [self.delegate chromiumBrowserView:self didChangeFaviconURLs:urls];
    }
}

- (void)nf_fullscreenChanged:(BOOL)fullscreen {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didRequestFullscreen:)]) {
        [self.delegate chromiumBrowserView:self didRequestFullscreen:fullscreen];
    }
}

- (void)nf_progressChanged:(double)progress {
    self.loadingProgress = progress;
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didChangeLoadingProgress:)]) {
        [self.delegate chromiumBrowserView:self didChangeLoadingProgress:progress];
    }
}

- (void)nf_loadingStateChangedLoading:(BOOL)isLoading canGoBack:(BOOL)canGoBack canGoForward:(BOOL)canGoForward {
    self.isLoading = isLoading;
    self.canGoBack = canGoBack;
    self.canGoForward = canGoForward;
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserViewDidChangeLoadingState:)]) {
        [self.delegate chromiumBrowserViewDidChangeLoadingState:self];
    }
}

- (void)nf_loadStarted:(NSURL *)url {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didStartNavigationToURL:)]) {
        [self.delegate chromiumBrowserView:self didStartNavigationToURL:url];
    }
}

- (void)nf_loadEnded:(NSURL *)url httpStatusCode:(int)httpStatusCode {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:didFinishNavigationToURL:httpStatusCode:)]) {
        [self.delegate chromiumBrowserView:self didFinishNavigationToURL:url httpStatusCode:httpStatusCode];
    }
}

- (void)nf_loadFailed:(NSURL *)url errorCode:(int)errorCode errorText:(NSString *)errorText {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:
                                                    didFailNavigationToURL:errorCode:errorText:)]) {
        [self.delegate chromiumBrowserView:self didFailNavigationToURL:url errorCode:errorCode errorText:errorText];
    }
}

- (void)nf_requestNewTabWithURL:(NSURL *)url userGesture:(BOOL)userGesture inBackground:(BOOL)inBackground {
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:
                                                   didRequestNewTabWithURL:userGesture:inBackground:)]) {
        [self.delegate chromiumBrowserView:self
                   didRequestNewTabWithURL:url
                               userGesture:userGesture
                              inBackground:inBackground];
    }
}

- (void)nf_browserDidClose {
    _browser = nullptr;
    _devToolsRegistration = nullptr;
    for (NFDevToolsCompletion completion in _devToolsCompletions.allValues) {
        completion(nil, NFChromiumError(1, @"The browser is closed."));
    }
    [_devToolsCompletions removeAllObjects];
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserViewDidClose:)]) {
        [self.delegate chromiumBrowserViewDidClose:self];
    }
}

- (BOOL)nf_runJavaScriptDialog:(NFChromiumJavaScriptDialogType)type
                       message:(NSString *)message
             defaultPromptText:(NSString *)defaultPromptText
                      callback:(CefRefPtr<CefJSDialogCallback>)callback {
    id<NFChromiumBrowserViewDelegate> delegate = self.delegate;
    SEL selector = @selector(chromiumBrowserView:runJavaScriptDialogOfType:message:defaultPromptText:completion:);
    if (![delegate respondsToSelector:selector]) {
        return NO;
    }
    // Leave Chromium's message loop first: app dialogs run modally.
    __weak NFChromiumBrowserView *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      NFChromiumBrowserView *view = weakSelf;
      if (!view) {
          callback->Continue(false, CefString());
          return;
      }
      [delegate chromiumBrowserView:view
          runJavaScriptDialogOfType:type
                            message:message
                  defaultPromptText:defaultPromptText
                         completion:^(BOOL accepted, NSString *userInput) {
                           callback->Continue(accepted, userInput.UTF8String ?: "");
                         }];
    });
    return YES;
}

- (NFChromiumDownload *)downloadForItem:(CefRefPtr<CefDownloadItem>)item {
    NSNumber *key = @(item->GetId());
    NFChromiumDownload *download = _downloads[key];
    if (!download) {
        download = [[NFChromiumDownload alloc] initWithIdentifier:item->GetId()];
        _downloads[key] = download;
    }
    [download updateWithItem:item];
    return download;
}

- (BOOL)nf_beforeDownload:(CefRefPtr<CefDownloadItem>)item
            suggestedName:(NSString *)suggestedName
                 callback:(CefRefPtr<CefBeforeDownloadCallback>)callback {
    NFChromiumDownload *download = [self downloadForItem:item];
    id<NFChromiumBrowserViewDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(chromiumBrowserView:decideDestinationForDownload:completion:)]) {
        NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory
                                                                inDomains:NSUserDomainMask]
                               .firstObject;
        NSString *name = suggestedName.length > 0 ? suggestedName : download.suggestedFileName;
        callback->Continue([downloads URLByAppendingPathComponent:name].path.UTF8String, false);
        return YES;
    }
    // Dropping the callback without calling Continue cancels the download.
    __block CefRefPtr<CefBeforeDownloadCallback> pending = callback;
    [delegate chromiumBrowserView:self
        decideDestinationForDownload:download
                          completion:^(NSURL *destination) {
                            if (pending && destination.isFileURL) {
                                pending->Continue(destination.path.UTF8String, false);
                            }
                            pending = nullptr;
                          }];
    return YES;
}

- (void)nf_downloadUpdated:(CefRefPtr<CefDownloadItem>)item callback:(CefRefPtr<CefDownloadItemCallback>)callback {
    NFChromiumDownload *download = [self downloadForItem:item];
    download.cancelHandler = ^{
      callback->Cancel();
    };
    if (download.cancelRequested && download.isInProgress) {
        callback->Cancel();
    }
    if ([self.delegate respondsToSelector:@selector(chromiumBrowserView:downloadDidUpdate:)]) {
        [self.delegate chromiumBrowserView:self downloadDidUpdate:download];
    }
    if (download.isComplete || download.isCanceled) {
        download.cancelHandler = nil;
        [_downloads removeObjectForKey:@(download.identifier)];
    }
}

- (BOOL)nf_requestMediaAccessForOrigin:(NSURL *)origin
                           permissions:(uint32_t)permissions
                              callback:(CefRefPtr<CefMediaAccessCallback>)callback {
    id<NFChromiumBrowserViewDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(chromiumBrowserView:
                                          requestMediaAccessForOrigin:video:audio:decision:)]) {
        return NO;
    }
    BOOL video = (permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0;
    BOOL audio = (permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0;
    [delegate chromiumBrowserView:self
        requestMediaAccessForOrigin:origin
                              video:video
                              audio:audio
                           decision:^(BOOL granted) {
                             if (granted) {
                                 callback->Continue(permissions);
                             } else {
                                 callback->Cancel();
                             }
                           }];
    return YES;
}

@end
