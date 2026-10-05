import SwiftUI
@preconcurrency import WebKit

struct CrossEngineSplitView: View {
    @ObservedObject var tab: Tab
    let onCaptureScreenshot: () -> Void

    @State private var webkitWebView: WKWebView?
    @State private var chromiumWebView: WKWebView?
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
                        subTitle: "Blink 131.0 Engine",
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
                chromiumWebView?.reload()
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

    @ViewBuilder
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

            // Webview frame
            EngineWebViewHost(
                url: tab.currentPageURL ?? tab.url,
                engineKind: engineKind,
                spaceID: tab.container.id,
                onWebViewCreated: { wv in
                    if engineKind == .webkit {
                        webkitWebView = wv
                    } else {
                        chromiumWebView = wv
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EngineWebViewHost: NSViewRepresentable {
    let url: URL
    let engineKind: BrowserEngineKind
    let spaceID: UUID
    let onWebViewCreated: (WKWebView) -> Void

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let id = UUID()
        weak var webView: WKWebView?

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
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
        let profile = BrowserEngine.shared.makeProfile(
            engineKind: engineKind,
            identifier: spaceID,
            isPrivate: false
        )
        config.websiteDataStore = profile.dataStore
        config.userContentController.add(DeviceSyncBridge.shared, name: DeviceSyncBridge.messageName)

        let syncUserScript = WKUserScript(
            source: DeviceSyncBridge.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(syncUserScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let ua = switch engineKind {
        case .webkit:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        case .chromium:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        }
        webView.customUserAgent = ua
        webView.load(URLRequest(url: url))

        DeviceSyncBridge.shared.register(id: context.coordinator.id, webView: webView)

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        DeviceSyncBridge.shared.unregister(id: coordinator.id)
        nsView.stopLoading()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: DeviceSyncBridge.messageName)
    }
}
