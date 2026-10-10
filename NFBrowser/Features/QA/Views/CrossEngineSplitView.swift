import SwiftUI
@preconcurrency import WebKit

struct CrossEngineSplitView: View {
    @ObservedObject var tab: Tab
    let onCaptureScreenshot: () -> Void

    @State private var webkitWebView: WKWebView?
    @State private var chromiumView: NFChromiumBrowserView?
    @State private var webkitURL: URL?
    @State private var chromiumURL: URL?

    var body: some View {
        ZStack(alignment: .top) {
            Color(NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top control bar
                controlBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .zIndex(10)

                // 50/50 Split View
                HStack(spacing: 2) {
                    // Left: WebKit Pane
                    enginePane(
                        title: "WebKit",
                        subTitle: "Safari 18.3 Engine",
                        icon: "safari",
                        engineKind: .webkit,
                        accentColor: Color.blue
                    )

                    // Right: Chromium Pane
                    enginePane(
                        title: "Chromium",
                        subTitle: "Blink · Chromium \(NFChromiumRuntime.shared.chromiumVersion)",
                        icon: "globe",
                        engineKind: .chromium,
                        accentColor: Color.green
                    )
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .onAppear {
            webkitURL = tab.url
            chromiumURL = tab.url
        }
        .onChange(of: tab.url) { _, newURL in
            if tab.qaState.isSyncEnabled {
                webkitURL = newURL
                chromiumURL = newURL
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Mode Indicator
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                Text("Cross-Engine Compare")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }

            Divider()
                .frame(height: 14)
                .background(Color.white.opacity(0.2))

            // Sync Toggle
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    tab.qaState.isSyncEnabled.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: tab.qaState.isSyncEnabled ? "link" : "link.slash")
                        .font(.system(size: 11))
                    Text(tab.qaState.isSyncEnabled ? "Sync: ON" : "Sync: OFF")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(tab.qaState.isSyncEnabled ? Color.accentColor : .white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(tab.qaState.isSyncEnabled ? Color.accentColor.opacity(0.15) : Color.white.opacity(0.08))
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Synchronize scrolling and clicks between engines")

            // Reload Both
            Button {
                webkitWebView?.reload()
                chromiumView?.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reload both engines")

            // Screenshot
            Button {
                onCaptureScreenshot()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Capture screenshot")

            Spacer()

            // Close
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    tab.qaState.toggleCrossEngine()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Exit Cross-Engine Compare")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(NSColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.95)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        )
    }

    private func enginePane(
        title: String,
        subTitle: String,
        icon: String,
        engineKind: BrowserEngineKind,
        accentColor: Color
    ) -> some View {
        VStack(spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(subTitle)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Engine view: each pane runs its real engine on the Space's own profile.
            Group {
                switch engineKind {
                case .webkit:
                    WebKitEngineHost(url: paneURL(for: .webkit), spaceID: tab.container.id) { webkitWebView = $0 }
                case .chromium:
                    ChromiumEngineHost(url: paneURL(for: .chromium), spaceID: tab.container.id) { chromiumView = $0 }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneURL(for engineKind: BrowserEngineKind) -> URL {
        let followed = engineKind == .webkit ? webkitURL : chromiumURL
        return followed ?? tab.currentPageURL ?? tab.url
    }
}

/// WebKit pane: a WKWebView on the Space's WebKit store, mirrored with the Chromium pane.
private struct WebKitEngineHost: NSViewRepresentable {
    let url: URL
    let spaceID: UUID
    let onWebViewCreated: (WKWebView) -> Void

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let id = UUID()
        var loadedURL: URL?

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let profile = BrowserEngine.shared.makeProfile(engineKind: .webkit, identifier: spaceID, isPrivate: false)
        config.websiteDataStore = profile.dataStore
        config.userContentController.add(DeviceSyncBridge.shared, name: DeviceSyncBridge.messageName)
        config.userContentController.addUserScript(WKUserScript(
            source: DeviceSyncBridge.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.customUserAgent = BrowserPageConfiguration
            .oraDefault(engineKind: .webkit, userScripts: [], privacySettings: .init())
            .userAgent
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url

        DeviceSyncBridge.shared.register(id: context.coordinator.id, peer: webView)
        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        DeviceSyncBridge.shared.unregister(id: coordinator.id)
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: DeviceSyncBridge.messageName)
    }
}

/// Chromium pane: a real Chromium browser on the Space's Chromium profile.
private struct ChromiumEngineHost: NSViewRepresentable {
    let url: URL
    let spaceID: UUID
    let onViewCreated: (NFChromiumBrowserView) -> Void

    final class Coordinator: NSObject, NFChromiumBrowserViewDelegate {
        let id = UUID()
        var loadedURL: URL?

        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            didReceiveDevToolsEvent method: String,
            params: [String: Any]
        ) {
            DeviceSyncBridge.shared.handleChromiumEvent(method: method, params: params, from: view)
        }

        /// Links that would open a tab stay in the pane, as in the WebKit pane.
        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            didRequestNewTabWith url: URL,
            userGesture: Bool,
            inBackground: Bool
        ) {
            view.load(url)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NFChromiumBrowserView {
        let view = NFChromiumBrowserView(
            frame: .zero,
            profileIdentifier: spaceID.uuidString,
            persistent: true,
            initialURL: url
        )
        view.delegate = context.coordinator
        view.observedDevToolsEvents = ["Runtime.bindingCalled"]
        context.coordinator.loadedURL = url
        DeviceSyncBridge.shared.installChromiumBridge(on: view)
        DeviceSyncBridge.shared.register(id: context.coordinator.id, peer: view)
        DispatchQueue.main.async {
            onViewCreated(view)
        }
        return view
    }

    func updateNSView(_ view: NFChromiumBrowserView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        view.load(url)
    }

    static func dismantleNSView(_ view: NFChromiumBrowserView, coordinator: Coordinator) {
        DeviceSyncBridge.shared.unregister(id: coordinator.id)
        view.closeBrowser()
    }
}
