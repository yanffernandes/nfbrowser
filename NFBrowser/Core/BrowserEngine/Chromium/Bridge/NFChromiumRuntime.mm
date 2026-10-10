#import "NFChromiumRuntime+Internal.h"

#import <AppKit/AppKit.h>
#include <crt_externs.h>

#include <climits>
#include <map>
#include <memory>
#include <string>

#include "include/cef_app.h"
#include "include/cef_callback.h"
#include "include/cef_cookie.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

#import "NFChromiumApplication.h"

static NSString *const NFChromiumErrorDomain = @"NFChromiumRuntime";

@interface NFChromiumRuntime ()
- (void)nf_contextDidInitialize;
@end

// Where earlier builds kept profiles waiting for removal, per root.
static NSString *const NFLegacyPendingRemovalsKeyPrefix = @"NFChromiumPendingProfileRemovals-";

// External message pump, ported from cefclient's MainMessageLoopExternalPump(Mac)
// (tests/shared/browser in the CEF repository, BSD license,
// (c) The Chromium Embedded Framework Authors).
static const int64_t kMaxTimerDelayMs = 1000 / 30;
static const int64_t kTimerDelayPlaceholder = INT_MAX;

@interface NFChromiumPump : NSObject
- (void)scheduleWork:(int64_t)delayMs;
- (void)stop;
@end

@implementation NFChromiumPump {
    NSThread *_ownerThread;
    NSTimer *_timer;
    BOOL _isActive;
    BOOL _reentrancyDetected;
    BOOL _stopped;
}

- (instancetype)init {
    if ((self = [super init])) {
        _ownerThread = [NSThread currentThread];
    }
    return self;
}

// May be called on any thread. performSelector keeps working inside nested run
// loops (menus, modal panels), unlike the serial main dispatch queue.
- (void)scheduleWork:(int64_t)delayMs {
    [self performSelector:@selector(handleScheduleWork:)
                 onThread:_ownerThread
               withObject:@(delayMs)
            waitUntilDone:NO];
}

- (void)stop {
    _stopped = YES;
    [self killTimer];
}

- (void)handleScheduleWork:(NSNumber *)delay {
    if (_stopped) {
        return;
    }
    int64_t delayMs = delay.longLongValue;
    if (delayMs == kTimerDelayPlaceholder && _timer != nil) {
        return;
    }
    [self killTimer];
    if (delayMs <= 0) {
        [self doWork];
    } else {
        [self setTimer:MIN(delayMs, kMaxTimerDelayMs)];
    }
}

- (void)timerFired:(NSTimer *)timer {
    [self killTimer];
    if (!_stopped) {
        [self doWork];
    }
}

- (void)doWork {
    BOOL wasReentrant = [self performMessageLoopWork];
    if (wasReentrant) {
        [self scheduleWork:0];
    } else if (_timer == nil) {
        [self scheduleWork:kTimerDelayPlaceholder];
    }
}

- (BOOL)performMessageLoopWork {
    if (_isActive) {
        _reentrancyDetected = YES;
        return NO;
    }
    _reentrancyDetected = NO;
    _isActive = YES;
    CefDoMessageLoopWork();
    _isActive = NO;
    return _reentrancyDetected;
}

- (void)setTimer:(int64_t)delayMs {
    _timer = [NSTimer timerWithTimeInterval:(double)delayMs / 1000.0
                                     target:self
                                   selector:@selector(timerFired:)
                                   userInfo:nil
                                    repeats:NO];
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [runLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [runLoop addTimer:_timer forMode:NSEventTrackingRunLoopMode];
}

- (void)killTimer {
    [_timer invalidate];
    _timer = nil;
}

@end

namespace {

class NFCefApp : public CefApp, public CefBrowserProcessHandler {
   public:
    explicit NFCefApp(NFChromiumPump *pump) : pump_(pump) {}

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }

    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override {
        // Native notifications start Chromium's alerts helper, which asks for macOS
        // notification permission at launch; the embedded engine has no notification UI.
        command_line->AppendSwitchWithValue("disable-features", "NativeNotifications,SystemNotifications");
#if defined(DEBUG) && DEBUG
        // Ad-hoc signed dev builds change identity on every build, so the real
        // Keychain would prompt for "Safe Storage" access each time.
        command_line->AppendSwitch("use-mock-keychain");
#endif
    }

    void OnContextInitialized() override { [NFChromiumRuntime.shared nf_contextDidInitialize]; }

    void OnScheduleMessagePumpWork(int64_t delay_ms) override { [pump_ scheduleWork:delay_ms]; }

    // A second launch with the same root cache path lands here; there is no
    // default Chromium window to open, so report it as handled.
    bool OnAlreadyRunningAppRelaunch(CefRefPtr<CefCommandLine> command_line,
                                     const CefString &current_directory) override {
        return true;
    }

   private:
    NFChromiumPump *pump_;
    IMPLEMENT_REFCOUNTING(NFCefApp);
};

// Adapters from Objective-C blocks to CEF callback interfaces.
// Runs work queued for a request context once Chromium has initialized it: a profile
// on disk loads asynchronously, and its preferences can't be changed before that.
class NFRequestContextHandler : public CefRequestContextHandler {
   public:
    void OnRequestContextInitialized(CefRefPtr<CefRequestContext> context) override {
        initialized_ = true;
        NSArray<dispatch_block_t> *blocks = [pending_ copy];
        [pending_ removeAllObjects];
        for (dispatch_block_t block in blocks) {
            block();
        }
    }

    void PerformWhenInitialized(dispatch_block_t block) {
        if (initialized_) {
            block();
        } else {
            [pending_ addObject:block];
        }
    }

   private:
    bool initialized_ = false;
    NSMutableArray<dispatch_block_t> *pending_ = [NSMutableArray array];
    IMPLEMENT_REFCOUNTING(NFRequestContextHandler);
};

class NFCompletionCallback : public CefCompletionCallback {
   public:
    explicit NFCompletionCallback(void (^block)(void)) : block_(block) {}
    void OnComplete() override { block_(); }

   private:
    void (^block_)(void);
    IMPLEMENT_REFCOUNTING(NFCompletionCallback);
};

class NFSetCookieCallback : public CefSetCookieCallback {
   public:
    explicit NFSetCookieCallback(void (^block)(bool)) : block_(block) {}
    void OnComplete(bool success) override { block_(success); }

   private:
    void (^block_)(bool);
    IMPLEMENT_REFCOUNTING(NFSetCookieCallback);
};

class NFDeleteCookiesCallback : public CefDeleteCookiesCallback {
   public:
    explicit NFDeleteCookiesCallback(void (^block)(void)) : block_(block) {}
    void OnComplete(int num_deleted) override { block_(); }

   private:
    void (^block_)(void);
    IMPLEMENT_REFCOUNTING(NFDeleteCookiesCallback);
};

// Deletes the cookies a host receives: its own and its parent domains'. CEF releases
// the visitor when the visit ends, which is when completion is reported.
class NFHostCookieDeleter : public CefCookieVisitor {
   public:
    NFHostCookieDeleter(std::string host, void (^completion)(void)) : host_(std::move(host)), completion_(completion) {}
    ~NFHostCookieDeleter() override { dispatch_async(dispatch_get_main_queue(), completion_); }

    bool Visit(const CefCookie &cookie, int count, int total, bool &deleteCookie) override {
        std::string domain = CefString(&cookie.domain).ToString();
        if (!domain.empty() && domain[0] == '.') {
            domain.erase(0, 1);
        }
        const std::string suffix = "." + domain;
        deleteCookie = !domain.empty() &&
                       (host_ == domain || (host_.size() > suffix.size() &&
                                            host_.compare(host_.size() - suffix.size(), suffix.size(), suffix) == 0));
        return true;
    }

   private:
    std::string host_;
    void (^completion_)(void);
    IMPLEMENT_REFCOUNTING(NFHostCookieDeleter);
};

// Chromium time is microseconds since 1601-01-01 UTC.
CefBaseTime NFBaseTime(NSDate *date) {
    cef_basetime_t time;
    time.val = static_cast<int64_t>((date.timeIntervalSince1970 + 11644473600.0) * 1000000.0);
    return CefBaseTime(time);
}

CefCookie NFCefCookie(NSHTTPCookie *cookie) {
    CefCookie cefCookie;
    NSString *path = cookie.path.length > 0 ? cookie.path : @"/";
    CefString(&cefCookie.name) = cookie.name.UTF8String;
    CefString(&cefCookie.value) = cookie.value.UTF8String;
    // An empty domain makes a host-only cookie for the URL's host.
    CefString(&cefCookie.domain) = [cookie.domain hasPrefix:@"."] ? cookie.domain.UTF8String : "";
    CefString(&cefCookie.path) = path.UTF8String;
    cefCookie.secure = cookie.isSecure;
    cefCookie.httponly = cookie.isHTTPOnly;
    if (cookie.expiresDate) {
        cefCookie.has_expires = true;
        cefCookie.expires = NFBaseTime(cookie.expiresDate);
    }
    if ([cookie.sameSitePolicy isEqualToString:NSHTTPCookieSameSiteStrict]) {
        cefCookie.same_site = CEF_COOKIE_SAME_SITE_STRICT_MODE;
    } else if ([cookie.sameSitePolicy isEqualToString:NSHTTPCookieSameSiteLax]) {
        cefCookie.same_site = CEF_COOKIE_SAME_SITE_LAX_MODE;
    }
    return cefCookie;
}

std::string NFCookieURL(NSHTTPCookie *cookie) {
    NSString *host = [cookie.domain stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
    NSString *path = cookie.path.length > 0 ? cookie.path : @"/";
    return [NSString stringWithFormat:@"%@://%@%@", cookie.isSecure ? @"https" : @"http", host, path].UTF8String;
}

std::string SanitizedProfileComponent(NSString *identifier) {
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
                            @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"];
    if (identifier.length > 0 &&
        [identifier rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) {
        return identifier.UTF8String;
    }
    return [NSString stringWithFormat:@"profile-%lx", (unsigned long)identifier.hash].UTF8String;
}

}  // namespace

@implementation NFChromiumRuntime {
    std::unique_ptr<CefScopedLibraryLoader> _libraryLoader;
    CefRefPtr<NFCefApp> _app;
    NFChromiumPump *_pump;
    std::map<std::string, CefRefPtr<CefRequestContext>> _requestContexts;
    std::map<int, CefRefPtr<CefBrowser>> _browsers;
    NSMutableArray<dispatch_block_t> *_contextReadyBlocks;
    BOOL _contextReady;
    BOOL _initializationFailed;
}

+ (NFChromiumRuntime *)shared {
    static NFChromiumRuntime *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      shared = [[NFChromiumRuntime alloc] initPrivate];
    });
    return shared;
}

- (instancetype)initPrivate {
    if ((self = [super init])) {
        _cefVersion = @CEF_VERSION;
        _chromiumVersion = [NSString stringWithFormat:@"%d.%d.%d.%d", CHROME_VERSION_MAJOR, CHROME_VERSION_MINOR,
                                                      CHROME_VERSION_BUILD, CHROME_VERSION_PATCH];
        _rootCacheURL = [NFChromiumRuntime defaultRootCacheURL];
        _contextReadyBlocks = [NSMutableArray array];
    }
    return self;
}

- (void)performWhenContextReady:(dispatch_block_t)block {
    if (_contextReady) {
        block();
    } else {
        [_contextReadyBlocks addObject:[block copy]];
    }
}

- (void)nf_contextDidInitialize {
    _contextReady = YES;
    NSArray<dispatch_block_t> *blocks = [_contextReadyBlocks copy];
    [_contextReadyBlocks removeAllObjects];
    for (dispatch_block_t block in blocks) {
        block();
    }
}

+ (NSURL *)defaultRootCacheURL {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask]
                         .firstObject;
    // CEF allows one process per root cache path, and dev builds run next to the
    // installed app, so they get their own root.
    BOOL installed = [NSBundle.mainBundle.bundlePath hasPrefix:@"/Applications/"];
    NSString *name = installed ? @"Chromium" : @"Chromium-Dev";
    return [[support URLByAppendingPathComponent:@"NFBrowser" isDirectory:YES] URLByAppendingPathComponent:name
                                                                                              isDirectory:YES];
}

+ (NSString *)acceptLanguageList {
    return [NSLocale.preferredLanguages componentsJoinedByString:@","];
}

- (NSInteger)liveBrowserCount {
    return (NSInteger)_browsers.size();
}

- (BOOL)startIfNeededWithError:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"NFChromiumRuntime must be used on the main thread");
    if (_isRunning) {
        return YES;
    }
    if (_initializationFailed) {
        return [self fail:error code:3 description:@"Chromium failed to initialize earlier in this session."];
    }
    if (![NSApp isKindOfClass:[NFChromiumApplication class]]) {
        return [self fail:error code:1 description:@"NSApp is not NFChromiumApplication; see App/main.swift."];
    }
    [NSFileManager.defaultManager createDirectoryAtURL:_rootCacheURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    // CEF compares profile paths against the realpath of the root (/tmp is
    // /private/tmp); NSURL's symlink resolution strips /private instead.
    char resolvedRoot[PATH_MAX];
    if (realpath(_rootCacheURL.fileSystemRepresentation, resolvedRoot) != nullptr) {
        _rootCacheURL = [NSURL fileURLWithFileSystemRepresentation:resolvedRoot isDirectory:YES relativeToURL:nil];
    }

    [self applyPendingProfileRemovals];

    _libraryLoader = std::make_unique<CefScopedLibraryLoader>();
    if (!_libraryLoader->LoadInMain()) {
        _libraryLoader.reset();
        _initializationFailed = YES;
        return [self fail:error code:2 description:@"Could not load Chromium Embedded Framework.framework."];
    }

    CefMainArgs mainArgs(*_NSGetArgc(), *_NSGetArgv());
    CefSettings settings;
    // Helpers enter Chromium's process sandbox (see ChromiumHelper/main.mm).
    settings.no_sandbox = false;
    settings.external_message_pump = true;
    settings.command_line_args_disabled = true;
    settings.persist_session_cookies = true;
    settings.log_severity = LOGSEVERITY_WARNING;
    CefString(&settings.root_cache_path) = _rootCacheURL.path.UTF8String;
    CefString(&settings.log_file) = [_rootCacheURL URLByAppendingPathComponent:@"chromium.log"].path.UTF8String;
    CefString(&settings.accept_language_list) = [NFChromiumRuntime acceptLanguageList].UTF8String;

    _pump = [[NFChromiumPump alloc] init];
    _app = new NFCefApp(_pump);
    if (!CefInitialize(mainArgs, settings, _app.get(), nullptr)) {
        _initializationFailed = YES;
        [_pump stop];
        NSString *message = [NSString stringWithFormat:@"CefInitialize failed (exit code %d).", CefGetExitCode()];
        return [self fail:error code:3 description:message];
    }
    _isRunning = YES;
    return YES;
}

- (void)shutdown {
    if (!_isRunning) {
        return;
    }
    [_pump stop];
    for (auto &entry : _browsers) {
        entry.second->GetHost()->CloseBrowser(true);
    }
    // OnBeforeClose can fail to arrive for child-view browsers (CEF issue 3810),
    // so the wait is bounded.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!_browsers.empty() && deadline.timeIntervalSinceNow > 0) {
        CefDoMessageLoopWork();
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    for (int i = 0; i < 10; ++i) {
        CefDoMessageLoopWork();
        [NSThread sleepForTimeInterval:0.02];
    }
    _browsers.clear();
    _requestContexts.clear();
    [_contextReadyBlocks removeAllObjects];
    CefShutdown();
    _isRunning = NO;
    _contextReady = NO;
}

- (CefRefPtr<CefRequestContext>)requestContextForProfile:(NSString *)identifier persistent:(BOOL)persistent {
    std::string component = SanitizedProfileComponent(identifier);
    std::string key = (persistent ? "persistent:" : "ephemeral:") + component;
    auto existing = _requestContexts.find(key);
    if (existing != _requestContexts.end()) {
        return existing->second;
    }

    CefRequestContextSettings settings;
    settings.persist_session_cookies = persistent;
    CefString(&settings.accept_language_list) = [NFChromiumRuntime acceptLanguageList].UTF8String;
    if (persistent) {
        // Must be a direct child of root_cache_path; anything deeper silently
        // becomes an incognito profile.
        NSString *path = [_rootCacheURL URLByAppendingPathComponent:@(component.c_str()) isDirectory:YES].path;
        CefString(&settings.cache_path) = path.UTF8String;
    }
    CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, new NFRequestContextHandler());
    _requestContexts[key] = context;
    return context;
}

// Runs `block` with the profile's request context once Chromium has initialized it.
- (void)performWhenProfileReady:(NSString *)identifier
                     persistent:(BOOL)persistent
                          block:(void (^)(CefRefPtr<CefRequestContext> context))block {
    CefRefPtr<CefRequestContext> context = [self requestContextForProfile:identifier persistent:persistent];
    // Every context is created above with this handler.
    static_cast<NFRequestContextHandler *>(context->GetHandler().get())->PerformWhenInitialized(^{
      block(context);
    });
}

#pragma mark Profile data

// Runs `block` with the profile's cookie manager once its storage is ready, or with
// nullptr when Chromium cannot start.
- (void)withCookieManagerForProfile:(NSString *)identifier
                         persistent:(BOOL)persistent
                              block:(void (^)(CefRefPtr<CefCookieManager> manager))block {
    if (![self startIfNeededWithError:nil]) {
        block(nullptr);
        return;
    }
    __weak NFChromiumRuntime *weakSelf = self;
    [self performWhenContextReady:^{
      NFChromiumRuntime *runtime = weakSelf;
      if (!runtime.isRunning) {
          block(nullptr);
          return;
      }
      CefRefPtr<CefRequestContext> context = [runtime requestContextForProfile:identifier persistent:persistent];
      __block CefRefPtr<CefCookieManager> manager;
      manager = context->GetCookieManager(new NFCompletionCallback(^{
        block(manager);
      }));
      if (!manager) {
          block(nullptr);
      }
    }];
}

- (void)setCookies:(NSArray<NSHTTPCookie *> *)cookies
        forProfile:(NSString *)identifier
        persistent:(BOOL)persistent
        completion:(void (^)(NSInteger))completion {
    if (cookies.count == 0) {
        completion(0);
        return;
    }
    [self withCookieManagerForProfile:identifier
                           persistent:persistent
                                block:^(CefRefPtr<CefCookieManager> manager) {
                                  if (!manager) {
                                      completion(0);
                                      return;
                                  }
                                  __block NSInteger remaining = (NSInteger)cookies.count;
                                  __block NSInteger accepted = 0;
                                  void (^finishOne)(bool) = ^(bool success) {
                                    accepted += success ? 1 : 0;
                                    remaining -= 1;
                                    if (remaining == 0) {
                                        completion(accepted);
                                    }
                                  };
                                  for (NSHTTPCookie *cookie in cookies) {
                                      if (!manager->SetCookie(NFCookieURL(cookie), NFCefCookie(cookie),
                                                              new NFSetCookieCallback(finishOne))) {
                                          finishOne(false);
                                      }
                                  }
                                }];
}

- (void)deleteCookiesForProfile:(NSString *)identifier
                     persistent:(BOOL)persistent
                           host:(NSString *)host
                     completion:(void (^)(void))completion {
    [self withCookieManagerForProfile:identifier
                           persistent:persistent
                                block:^(CefRefPtr<CefCookieManager> manager) {
                                  if (!manager) {
                                      completion();
                                  } else if (host.length == 0) {
                                      if (!manager->DeleteCookies("", "", new NFDeleteCookiesCallback(completion))) {
                                          completion();
                                      }
                                  } else {
                                      // On failure the visitor is released at once and reports completion.
                                      manager->VisitAllCookies(
                                          new NFHostCookieDeleter(host.lowercaseString.UTF8String, completion));
                                  }
                                }];
}

- (void)setCookiePolicy:(NFChromiumCookiePolicy)policy forProfile:(NSString *)identifier persistent:(BOOL)persistent {
    if (![self startIfNeededWithError:nil]) {
        return;
    }
    __weak NFChromiumRuntime *weakSelf = self;
    [self performWhenContextReady:^{
      NFChromiumRuntime *runtime = weakSelf;
      if (!runtime.isRunning) {
          return;
      }
      [runtime performWhenProfileReady:identifier
                            persistent:persistent
                                 block:^(CefRefPtr<CefRequestContext> context) {
                                   [NFChromiumRuntime applyCookiePolicy:policy toContext:context];
                                 }];
    }];
}

+ (void)applyCookiePolicy:(NFChromiumCookiePolicy)policy toContext:(CefRefPtr<CefRequestContext>)context {
    // cookie_controls_mode 1 blocks third-party cookies; 0 allows them.
    CefRefPtr<CefValue> mode = CefValue::Create();
    mode->SetInt(policy == NFChromiumCookiePolicyAllowAll ? 0 : 1);
    // Blocking all cookies changes the profile's default cookie setting. CEF can't set
    // content-setting defaults on incognito profiles, but their preference works there
    // too; a null value restores Chromium's default (allow).
    CefRefPtr<CefValue> defaultSetting;
    if (policy == NFChromiumCookiePolicyBlockAll) {
        defaultSetting = CefValue::Create();
        defaultSetting->SetInt(CEF_CONTENT_SETTING_VALUE_BLOCK);
    }
    CefString error;
    if (!context->SetPreference("profile.cookie_controls_mode", mode, error) ||
        !context->SetPreference("profile.default_content_setting_values.cookies", defaultSetting, error)) {
        NSLog(@"[NFChromium] cookie policy: %s", error.ToString().c_str());
    }
}

- (void)clearCacheForProfile:(NSString *)identifier persistent:(BOOL)persistent completion:(void (^)(void))completion {
    if (![self startIfNeededWithError:nil]) {
        completion();
        return;
    }
    __weak NFChromiumRuntime *weakSelf = self;
    [self performWhenContextReady:^{
      NFChromiumRuntime *runtime = weakSelf;
      if (!runtime.isRunning) {
          completion();
          return;
      }
      [runtime requestContextForProfile:identifier persistent:persistent]->ClearHttpCache(
          new NFCompletionCallback(completion));
    }];
}

- (void)removeProfile:(NSString *)identifier {
    std::string component = SanitizedProfileComponent(identifier);
    _requestContexts.erase("persistent:" + component);
    _requestContexts.erase("ephemeral:" + component);
    NSString *name = @(component.c_str());
    if (!_isRunning) {
        [self deleteProfileDirectory:name];
        return;
    }
    // Chromium keeps the profile's files open until it exits.
    NSMutableArray *pending =
        [[NSArray arrayWithContentsOfURL:self.pendingRemovalsURL error:nil] mutableCopy] ?: [NSMutableArray array];
    if (![pending containsObject:name]) {
        [pending addObject:name];
    }
    [pending writeToURL:self.pendingRemovalsURL error:nil];
}

// Profiles removed while Chromium ran, deleted at its next start. The list lives in the
// root it refers to, so it goes wherever the profiles go.
- (NSURL *)pendingRemovalsURL {
    return [_rootCacheURL URLByAppendingPathComponent:@"NFBrowser Pending Removals.plist" isDirectory:NO];
}

- (void)applyPendingProfileRemovals {
    NSMutableSet *names = [NSMutableSet setWithArray:[NSArray arrayWithContentsOfURL:self.pendingRemovalsURL
                                                                               error:nil] ?: @[]];
    NSString *legacyKey = [NFLegacyPendingRemovalsKeyPrefix stringByAppendingString:_rootCacheURL.lastPathComponent];
    NSArray *legacyNames = [NSUserDefaults.standardUserDefaults stringArrayForKey:legacyKey];
    if (legacyNames) {
        [names addObjectsFromArray:legacyNames];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:legacyKey];
    }
    for (id name in names) {
        if ([name isKindOfClass:NSString.class]) {
            [self deleteProfileDirectory:name];
        }
    }
    [NSFileManager.defaultManager removeItemAtURL:self.pendingRemovalsURL error:nil];
}

- (void)deleteProfileDirectory:(NSString *)name {
    // Names come from SanitizedProfileComponent: a single path component.
    if (name.length == 0 || [name containsString:@"/"] || [name hasPrefix:@"."]) {
        return;
    }
    [NSFileManager.defaultManager removeItemAtURL:[_rootCacheURL URLByAppendingPathComponent:name isDirectory:YES]
                                            error:nil];
}

- (void)discardEphemeralProfile:(NSString *)identifier {
    _requestContexts.erase("ephemeral:" + SanitizedProfileComponent(identifier));
}

- (void)browserDidCreate:(CefRefPtr<CefBrowser>)browser {
    _browsers[browser->GetIdentifier()] = browser;
}

- (void)browserDidClose:(CefRefPtr<CefBrowser>)browser {
    _browsers.erase(browser->GetIdentifier());
}

- (BOOL)fail:(NSError **)error code:(NSInteger)code description:(NSString *)description {
    if (error) {
        *error = [NSError errorWithDomain:NFChromiumErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

@end
