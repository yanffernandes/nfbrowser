import AppKit
import SwiftData
import SwiftUI

enum TabType: String, Codable {
    case pinned
    case fav
    case normal
}

struct URLUpdate: Codable {
    let href: String
    let title: String
    let favicon: String?
}

// MARK: - Tab

@Model
class Tab: ObservableObject, Identifiable {
    var id: UUID
    var url: URL
    var urlString: String
    var savedURL: URL?
    var title: String
    var customTitle: String? = nil
    var favicon: URL? // Add favicon property
    var createdAt: Date
    var lastAccessedAt: Date?

    var displayTitle: String {
        if let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return title.isEmpty ? "New Tab" : title
    }

    var type: TabType
    var order: Int
    var faviconLocalFile: URL?
    var backgroundColorHex: String = "#000000"

    //    @Transient @Published var backgroundColor: Color = Color(.black)
    @Transient var isPlayingMedia: Bool = false
    @Transient var isLoading: Bool = false
    @Transient @Published var backgroundColor: Color = .black
    @Transient var historyManager: HistoryManager?
    @Transient var downloadManager: DownloadManager?
    @Transient var tabManager: TabManager?
    @Transient var browserPage: BrowserPage?
    @Transient var pageDelegate: TabBrowserPageDelegate?
    @Transient @Published var isWebViewReady: Bool = false
    @Transient @Published var loadingProgress: Double = 10.0
    @Transient var colorUpdated = false
    @Transient var maybeIsActive = false
    @Transient @Published var hasNavigationError: Bool = false
    @Transient @Published var navigationError: Error?
    @Transient @Published var failedURL: URL?
    @Transient @Published var hoveredLinkURL: String?
    @Transient var isPrivate: Bool = false
    @Transient var passwordCoordinator: PasswordAutofillCoordinator?
    @Transient @Published var passwordOverlayState: PasswordAutofillOverlayState?
    @Transient @Published var passwordTriggerOverlayState: PasswordAutofillOverlayState?
    @Transient @Published var isAgentActive: Bool = false
    @Transient @Published var agentStatusMessage: String? = nil
    @Transient private var agentActivityTask: Task<Void, Never>?

    @Relationship(inverse: \TabContainer.tabs) var container: TabContainer

    /// Whether this tab is considered alive (recently accessed)
    var isAlive: Bool {
        guard let lastAccessed = lastAccessedAt else { return false }
        let timeout = SettingsStore.shared.tabAliveTimeout
        return Date().timeIntervalSince(lastAccessed) < timeout
    }

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        customTitle: String? = nil,
        favicon: URL? = nil,
        container: TabContainer,
        type: TabType = .normal,
        isPlayingMedia: Bool = false,
        order: Int,
        historyManager: HistoryManager? = nil,
        downloadManager: DownloadManager? = nil,
        tabManager: TabManager? = nil,
        isPrivate: Bool = false
    ) {
        let nowDate = Date()
        self.id = id
        self.url = url
        self.urlString = url.absoluteString

        self.title = title
        self.customTitle = customTitle
        self.favicon = favicon
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
        self.type = type
        self.isPlayingMedia = isPlayingMedia
        self.container = container
        self.order = order
        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.tabManager = tabManager
        self.isPrivate = isPrivate
        self.passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        self.isWebViewReady = false
    }

    func syncBackgroundColorFromHex() {
        backgroundColor = Color(hex: backgroundColorHex)
    }

    /// Call this whenever the color is set
    func updateBackgroundColor(_ color: Color) {
        backgroundColor = color
        backgroundColorHex = color.toHex() ?? "#000000"
    }

    func setFavicon() {
        guard let host = self.url.host else { return }

        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard let faviconURL = FaviconService.shared.faviconURL(for: domain) else { return }
        self.favicon = faviconURL

        let fileName = "\(self.id.uuidString).png"
        let saveURL = FileManager.default.faviconDirectory.appendingPathComponent(fileName)

        FaviconService.shared
            .downloadAndSaveFavicon(for: domain, faviconURL: faviconURL, to: saveURL) {
                [weak self] sourceURL, success in
                guard let self else { return }
                if success {
                    Task { @MainActor in
                        self.faviconLocalFile = saveURL
                        if let sourceURL {
                            self.favicon = sourceURL
                        }
                    }
                }
            }
    }

    func switchSections(from: Tab, to: Tab) {
        from.type = to.type
        switch to.type {
        case .pinned, .fav:
            from.savedURL = from.url
        case .normal:
            from.savedURL = nil
        }
    }

    func updateHeaderColor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let page = self.browserPage, !page.isLoading else { return }
            self.pageDelegate?.takeSnapshotAfterLoad(page)
        }
    }

    func updateHistory() {
        if let historyManager = self.historyManager {
            Task { @MainActor in
                historyManager.record(
                    title: self.title,
                    url: self.url,
                    faviconURL: self.favicon,
                    faviconLocalFile: self.faviconLocalFile,
                    container: self.container
                )
            }
        }
    }

    func maintainSnapShots() {
        guard !self.colorUpdated, self.maybeIsActive else { return }
        self.updateHeaderColor()
    }

    func setupBrowserPageDelegate(for page: BrowserPage) {
        let delegate = TabBrowserPageDelegate()
        delegate.tab = self
        delegate.mediaController = tabManager?.mediaController
        delegate.passwordCoordinator = passwordCoordinator
        page.delegate = delegate
        pageDelegate = delegate
    }

    func goForward() {
        lastAccessedAt = Date()
        browserPage?.goForward()
        updateHeaderColor()
    }

    func goBack() {
        lastAccessedAt = Date()
        browserPage?.goBack()
        updateHeaderColor()
    }

    func restoreTransientState(
        historyManager: HistoryManager,
        downloadManager: DownloadManager,
        tabManager: TabManager,
        isPrivate: Bool
    ) {
        // Avoid double initialization
        if browserPage != nil { return }

        if passwordCoordinator == nil {
            passwordCoordinator = PasswordAutofillCoordinator(tab: self)
        }

        let engine = BrowserEngine.shared
        let engineKind = container.engineKind
        let profile = engine.makeProfile(engineKind: engineKind, identifier: container.id, isPrivate: isPrivate)
        let privacySettings = SettingsStore.shared.privacySettings(for: container.id)
        let userScripts = OraBrowserScripts.userScripts() + BrowserPrivacyService.privacyScripts(for: privacySettings)
        let page = engine.makePage(
            engineKind: engineKind,
            profile: profile,
            configuration: BrowserPageConfiguration.oraDefault(
                engineKind: engineKind,
                userScripts: userScripts,
                privacySettings: privacySettings
            ),
            delegate: nil
        )
        browserPage = page

        self.historyManager = historyManager
        self.downloadManager = downloadManager
        self.tabManager = tabManager
        self.isWebViewReady = false
        self.setupBrowserPageDelegate(for: page)
        self.syncBackgroundColorFromHex()
        // Load page immediately without artificial dispatch delay
        let url = if self.type != .normal { self.savedURL } else { self.url }
        page.load(URLRequest(url: url ?? self.url))
        self.isWebViewReady = true
    }

    func stopMedia(completed: @escaping () -> Void) {
        guard let page = browserPage else {
            completed()
            return
        }

        let js = """
        document.querySelectorAll('video, audio').forEach(el => {
            try {
                el.pause();
                el.src = '';
                el.load();
            } catch (e) {}
        });
        """
        page.evaluateJavaScript(js) { [weak self] _, _ in
            page.closeMediaPresentations {
                page.teardown()
                if self?.browserPage === page {
                    self?.browserPage = nil
                    self?.pageDelegate = nil
                }
                completed()
            }
        }
    }

    @MainActor
    func markAgentActive(status: String? = nil, duration: TimeInterval = 2.5) {
        agentActivityTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            self.isAgentActive = true
            self.agentStatusMessage = status
        }
        agentActivityTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                self.isAgentActive = false
                self.agentStatusMessage = nil
            }
        }
    }

    func loadURL(_ urlString: String) {
        lastAccessedAt = Date()
        let input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1) Try to construct a direct URL (has scheme or valid domain+TLD/IP)
        if let directURL = constructURL(from: input) {
            browserPage?.load(URLRequest(url: directURL))
            return
        }

        // 2) Otherwise, treat as a search query using the selected search engine
        let searchEngineService = SearchEngineService()
        if let engine = searchEngineService.getDefaultSearchEngine(for: self.container.id),
           let searchURL = searchEngineService.createSearchURL(for: engine, query: input)
        {
            browserPage?.load(URLRequest(url: searchURL))
            return
        }

        // 3) Fallback to Google if for some reason engine lookup fails
        if let fallbackURL = URL(string: "https://www.google.com/search?client=safari&rls=en&ie=UTF-8&oe=UTF-8&q="
            + (input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")
        ) {
            browserPage?.load(URLRequest(url: fallbackURL))
        }
    }

    func destroyWebView() {
        browserPage?.teardown()
        browserPage = nil
        pageDelegate = nil
        isWebViewReady = false
    }

    func setNavigationError(_ error: Error, for url: URL?) {
        DispatchQueue.main.async {
            self.hasNavigationError = true
            self.navigationError = error
            self.failedURL = url
        }
    }

    func clearNavigationError() {
        DispatchQueue.main.async {
            self.hasNavigationError = false
            self.navigationError = nil
            self.failedURL = nil
        }
    }

    func retryNavigation() {
        // Don't clear error state immediately - let onStart callback handle it
        // This prevents showing white background before navigation begins
        if let url = failedURL {
            let request = URLRequest(url: url)
            browserPage?.load(request)
        }
    }

    func continueToInsecureSite() {
        let url = failedURL ?? self.url
        guard let host = url.host else { return }
        browserPage?.bypassSSL(for: host)
        clearNavigationError()
        browserPage?.load(URLRequest(url: url))
    }

    var canGoBack: Bool {
        browserPage?.canGoBack ?? false
    }

    var canGoForward: Bool {
        browserPage?.canGoForward ?? false
    }

    var currentPageURL: URL? {
        browserPage?.currentURL
    }

    var pageWindow: NSWindow? {
        browserPage?.window
    }

    func reload() {
        browserPage?.reload()
    }

    func refreshBrowserPageForPrivacySettings() {
        guard isWebViewReady,
              let historyManager,
              let downloadManager,
              let tabManager
        else {
            return
        }

        destroyWebView()
        restoreTransientState(
            historyManager: historyManager,
            downloadManager: downloadManager,
            tabManager: tabManager,
            isPrivate: isPrivate
        )
    }

    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)? = nil) {
        browserPage?.evaluateJavaScript(script, completion: completion)
    }

    func takeSnapshot(
        configuration: BrowserSnapshotConfiguration,
        completion: @escaping (NSImage?, Error?) -> Void
    ) {
        browserPage?.takeSnapshot(configuration: configuration, completion: completion)
    }

    @MainActor
    func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = "Enter a custom title for this tab, or leave it blank to reset to the original title."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.stringValue = customTitle ?? title
        textField.isEditable = true
        textField.isSelectable = true
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        DispatchQueue.main.async {
            alert.window.makeFirstResponder(textField)
            textField.selectText(nil)
            if alert.runModal() == .alertFirstButtonReturn {
                let trimmed = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.customTitle = trimmed.isEmpty ? nil : trimmed
                try? self.tabManager?.modelContext.save()
            }
        }
    }

    @MainActor
    func resetTitle() {
        customTitle = nil
        try? tabManager?.modelContext.save()
    }
}

extension FileManager {
    var faviconDirectory: URL {
        let dir = urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Favicons")
        if !fileExists(atPath: dir.path) {
            try? createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        // swiftlint:disable:next identifier_name
        let r, g, b, a: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
            a = 1.0
        case 8:
            r = Double((int >> 24) & 0xFF) / 255
            g = Double((int >> 16) & 0xFF) / 255
            b = Double((int >> 8) & 0xFF) / 255
            a = Double(int & 0xFF) / 255
        default:
            return nil
        }

        self.init(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    func toHex() -> String? {
        guard let color = usingColorSpace(.deviceRGB) else { return nil }
        // swiftlint:disable:next identifier_name
        let r = Int(color.redComponent * 255)
        // swiftlint:disable:next identifier_name
        let g = Int(color.greenComponent * 255)
        // swiftlint:disable:next identifier_name
        let b = Int(color.blueComponent * 255)
        // swiftlint:disable:next identifier_name
        let a = Int(color.alphaComponent * 255)

        return a < 255
            ? String(format: "#%02X%02X%02X%02X", r, g, b, a)
            : String(format: "#%02X%02X%02X", r, g, b)
    }
}
