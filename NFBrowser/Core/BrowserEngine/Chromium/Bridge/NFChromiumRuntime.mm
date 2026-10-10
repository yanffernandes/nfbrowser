#import "NFChromiumRuntime+Internal.h"

#import <AppKit/AppKit.h>
#include <crt_externs.h>

#include <climits>
#include <map>
#include <memory>
#include <string>

#include "include/cef_app.h"
#include "include/cef_version.h"
#include "include/wrapper/cef_library_loader.h"

#import "NFChromiumApplication.h"

static NSString *const NFChromiumErrorDomain = @"NFChromiumRuntime";

@interface NFChromiumRuntime ()
- (void)nf_contextDidInitialize;
@end

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

    _libraryLoader = std::make_unique<CefScopedLibraryLoader>();
    if (!_libraryLoader->LoadInMain()) {
        _libraryLoader.reset();
        _initializationFailed = YES;
        return [self fail:error code:2 description:@"Could not load Chromium Embedded Framework.framework."];
    }

    CefMainArgs mainArgs(*_NSGetArgc(), *_NSGetArgv());
    CefSettings settings;
    settings.no_sandbox = true;
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
    CefRefPtr<CefRequestContext> context = CefRequestContext::CreateContext(settings, nullptr);
    _requestContexts[key] = context;
    return context;
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
