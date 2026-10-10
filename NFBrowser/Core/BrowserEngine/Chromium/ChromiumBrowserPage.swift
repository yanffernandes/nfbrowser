import AppKit

/// Page for Spaces whose engine is Chromium: Blink and V8 through CEF (Alloy style),
/// hosted in an `NFChromiumBrowserView`. Each Space maps to one Chromium profile.
final class ChromiumBrowserPage: NSObject, BrowserPage {
    let engineKind: BrowserEngineKind = .chromium
    weak var delegate: BrowserPageDelegate?
    private(set) var lastCommittedURL: URL?
    /// Chromium downloads never replace the page, so the tab is kept as is.
    let isDownloadNavigation = false

    private let browserView: NFChromiumBrowserView
    private let messageBindingName = "__nf" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var isBridgeReady = false
    private var pendingURL: URL?
    private var isNavigating = false
    private var downloads: [UInt32: ChromiumDownloadTask] = [:]

    init(profile: BrowserEngineProfile, configuration: BrowserPageConfiguration, delegate: BrowserPageDelegate?) {
        // Starts on about:blank: DevTools page commands are answered by the renderer,
        // so one has to exist before the bridge and scripts can be registered.
        browserView = NFChromiumBrowserView(
            frame: .zero,
            profileIdentifier: profile.identifier.uuidString,
            persistent: !profile.isPrivate,
            initialURL: URL(string: "about:blank")
        )
        self.delegate = delegate
        super.init()
        browserView.delegate = self
        browserView.observedDevToolsEvents = ["Runtime.bindingCalled"]
        installPageBridge(userScripts: configuration.userScripts)
    }

    var contentView: NSView {
        browserView
    }

    var window: NSWindow? {
        browserView.window
    }

    var currentURL: URL? {
        browserView.currentURL
    }

    var title: String? {
        browserView.title
    }

    var canGoBack: Bool {
        browserView.canGoBack
    }

    var canGoForward: Bool {
        browserView.canGoForward
    }

    var isLoading: Bool {
        browserView.isLoading
    }

    var estimatedProgress: Double {
        browserView.loadingProgress
    }

    func load(_ request: URLRequest) {
        guard let url = request.url else { return }
        guard isBridgeReady else {
            pendingURL = url
            return
        }
        browserView.load(url)
    }

    func reload() {
        browserView.reload()
    }

    func goBack() {
        browserView.goBack()
    }

    func goForward() {
        browserView.goForward()
    }

    func stopLoading() {
        browserView.stopLoading()
    }

    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)?) {
        browserView.evaluateJavaScript(script, completion: completion)
    }

    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping (NSImage?, Error?) -> Void
    ) {
        let viewSize = browserView.bounds.size
        browserView.captureScreenshot { image, error in
            guard let image, let rect = configuration.rect, viewSize.width > 0 else {
                completion(image, error)
                return
            }
            completion(image.cropped(to: rect, viewSize: viewSize), nil)
        }
    }

    func closeMediaPresentations(completion: @escaping () -> Void) {
        completion()
    }

    func teardown() {
        browserView.delegate = nil
        browserView.closeBrowser()
        browserView.removeFromSuperview()
    }

    func bypassSSL(for host: String) {
        browserView.allowedInsecureHosts = browserView.allowedInsecureHosts.union([host])
    }

    /// Registers the message binding and the user scripts before the first navigation,
    /// so no document loads without them.
    private func installPageBridge(userScripts: [BrowserUserScript]) {
        let sources = [ChromiumUserScripts.bridgeScript(bindingName: messageBindingName)]
            + userScripts.map(ChromiumUserScripts.chromiumSource(for:))
        // Page must be enabled for new-document scripts to run, and Runtime for the
        // binding to be installed in documents created by later navigations.
        browserView.sendDevToolsMethod("Page.enable", params: nil, completion: nil)
        browserView.sendDevToolsMethod("Runtime.enable", params: nil, completion: nil)
        browserView.sendDevToolsMethod("Runtime.addBinding", params: ["name": messageBindingName], completion: nil)

        let group = DispatchGroup()
        for source in sources {
            group.enter()
            browserView
                .sendDevToolsMethod("Page.addScriptToEvaluateOnNewDocument", params: ["source": source]) { _, _ in
                    group.leave()
                }
        }
        group.notify(queue: .main) { [weak self] in
            self?.bridgeDidBecomeReady()
        }
        // Never hold the first navigation hostage to the bridge.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.bridgeDidBecomeReady()
        }
    }

    private func bridgeDidBecomeReady() {
        guard !isBridgeReady else { return }
        isBridgeReady = true
        if let url = pendingURL {
            pendingURL = nil
            browserView.load(url)
        }
    }

    private func emitNavigation(_ phase: BrowserNavigationPhase, url: URL?, progress: Double, isLoading: Bool) {
        delegate?.browserPage(
            self,
            didUpdateNavigation: BrowserNavigationEvent(
                phase: phase,
                url: url,
                title: browserView.title,
                progress: progress,
                isLoading: isLoading
            )
        )
    }
}

// MARK: - NFChromiumBrowserViewDelegate

extension ChromiumBrowserPage: NFChromiumBrowserViewDelegate {
    func chromiumBrowserViewDidChangeLoadingState(_ view: NFChromiumBrowserView) {
        guard isBridgeReady else { return }
        if view.isLoading, !isNavigating {
            isNavigating = true
            emitNavigation(.started, url: view.currentURL, progress: 10, isLoading: true)
        } else if !view.isLoading, isNavigating {
            isNavigating = false
            emitNavigation(.finished, url: view.currentURL, progress: 100, isLoading: false)
        }
    }

    func chromiumBrowserView(_ view: NFChromiumBrowserView, didStartNavigationTo url: URL?) {
        guard isBridgeReady else { return }
        emitNavigation(.committed, url: url, progress: max(view.loadingProgress * 100, 10), isLoading: true)
    }

    func chromiumBrowserView(_ view: NFChromiumBrowserView, didFinishNavigationTo url: URL?, httpStatusCode: Int) {
        guard isBridgeReady else { return }
        lastCommittedURL = url ?? lastCommittedURL
        guard isNavigating else { return }
        isNavigating = false
        emitNavigation(.finished, url: url ?? view.currentURL, progress: 100, isLoading: false)
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        didFailNavigationTo url: URL?,
        errorCode: Int,
        errorText: String
    ) {
        isNavigating = false
        emitNavigation(.finished, url: view.currentURL, progress: 100, isLoading: false)
        delegate?.browserPage(
            self,
            didFailNavigationWith: ChromiumNetError.makeError(code: errorCode, text: errorText, url: url),
            failingURL: url
        )
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        didRequestNewTabWith url: URL,
        userGesture: Bool,
        inBackground: Bool
    ) {
        // Without a user gesture this is a pop-under or ad window; Chromium's own popup
        // blocker is not part of the embedded engine.
        guard userGesture else { return }
        if inBackground,
           delegate?.browserPage(
               self,
               decidePolicyFor: BrowserNavigationAction(request: URLRequest(url: url), modifierFlags: .command)
           ) == .openInNewTab
        {
            return
        }
        delegate?.browserPage(self, didRequestOpenInNewTab: url)
    }

    /// Chromium also titles pages that have no <title> (host and path), and titles can
    /// change after load; both reach the tab through the page scripts' update channel.
    func chromiumBrowserView(_ view: NFChromiumBrowserView, didChangeTitle title: String) {
        guard isBridgeReady, !title.isEmpty, let url = view.currentURL, url.scheme != "about",
              let data = try? JSONSerialization.data(withJSONObject: ["href": url.absoluteString, "title": title]),
              let body = String(data: data, encoding: .utf8)
        else { return }
        delegate?.browserPage(self, didReceiveScriptMessage: BrowserScriptMessage(name: "listener", body: body))
    }

    func chromiumBrowserViewDidClose(_ view: NFChromiumBrowserView) {
        delegate?.browserPageDidClose(self)
    }

    func chromiumBrowserView(_ view: NFChromiumBrowserView, didRequestFullscreen fullscreen: Bool) {
        guard let window = view.window, window.styleMask.contains(.fullScreen) != fullscreen else { return }
        window.toggleFullScreen(nil)
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        didReceiveDevToolsEvent method: String,
        params: [String: Any]
    ) {
        guard method == "Runtime.bindingCalled",
              params["name"] as? String == messageBindingName,
              let payload = params["payload"] as? String,
              let message = ChromiumUserScripts.message(fromBindingPayload: payload)
        else { return }
        delegate?.browserPage(self, didReceiveScriptMessage: message)
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        decideDestinationFor download: NFChromiumDownload,
        completion: @escaping (URL?) -> Void
    ) {
        let task = ChromiumDownloadTask(download: download)
        delegate?.browserPage(self, didStartDownload: task)
        guard let requestDestination = task.onDestinationRequest else {
            completion(nil)
            return
        }
        downloads[download.identifier] = task
        let response = URLResponse(
            url: task.originalURL,
            mimeType: download.mimeType.isEmpty ? nil : download.mimeType,
            expectedContentLength: Int(download.totalBytes),
            textEncodingName: nil
        )
        requestDestination(response, download.suggestedFileName, completion)
    }

    func chromiumBrowserView(_ view: NFChromiumBrowserView, downloadDidUpdate download: NFChromiumDownload) {
        guard let task = downloads[download.identifier] else { return }
        task.update(from: download)
        if download.isComplete || download.isCanceled {
            downloads[download.identifier] = nil
        }
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        requestMediaAccessFor origin: URL?,
        video: Bool,
        audio: Bool,
        decision: @escaping (Bool) -> Void
    ) {
        guard let delegate else {
            decision(false)
            return
        }
        delegate.browserPage(self, requestPermission: .mediaCapture, origin: origin) { result in
            decision(result == .grant)
        }
    }

    func chromiumBrowserView(
        _ view: NFChromiumBrowserView,
        runJavaScriptDialogOf type: NFChromiumJavaScriptDialogType,
        message: String,
        defaultPromptText: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let delegate else {
            completion(false, nil)
            return
        }
        switch type {
        case .confirm:
            delegate.browserPage(self, runJavaScriptConfirm: message) { completion($0, nil) }
        case .prompt:
            delegate.browserPage(self, runJavaScriptPrompt: message, defaultText: defaultPromptText) { text in
                completion(text != nil, text)
            }
        default:
            delegate.browserPage(self, runJavaScriptAlert: message)
            completion(true, nil)
        }
    }
}

private extension NSImage {
    /// `rect` is in the page view's top-left coordinates; the screenshot is in device pixels.
    func cropped(to rect: CGRect, viewSize: CGSize) -> NSImage? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = CGFloat(cgImage.width) / viewSize.width
        let pixelRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }
}
