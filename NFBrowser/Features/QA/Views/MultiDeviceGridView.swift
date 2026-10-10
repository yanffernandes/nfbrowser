import AppKit
import SwiftUI
@preconcurrency import WebKit

struct MultiDeviceGridView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var qaState: QAModeState
    let onScreenshot: () -> Void

    @State private var orientationOverrides: [ViewportPreset: Bool] = [:]
    @State private var reloadTokens: [ViewportPreset: UUID] = [:]

    init(tab: Tab, qaState: QAModeState? = nil, onScreenshot: @escaping () -> Void) {
        self.tab = tab
        self.qaState = qaState ?? tab.qaState
        self.onScreenshot = onScreenshot
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(qaState.multiDevicePresets) { preset in
                        deviceCard(for: preset)
                    }

                    // Add Device Card
                    addDeviceCard
                }
                .padding(.horizontal, 32)
                .padding(.top, 68)
                .padding(.bottom, 40)
            }

            // Top Floating Toolbar
            gridToolbar
                .padding(.top, 12)
        }
    }

    private var gridToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 12, weight: .bold))
                Text("Multi-Device Grid")
                    .font(.system(size: 12, weight: .semibold))
                Text("(\(qaState.multiDevicePresets.count))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            }
            .foregroundColor(.white)

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Sync toggle
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    qaState.isSyncEnabled.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: qaState.isSyncEnabled ? "link" : "link.badge.plus")
                        .font(.system(size: 11))
                    Text(qaState.isSyncEnabled ? "Sync ON" : "Sync OFF")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(qaState.isSyncEnabled ? Color.green : .white.opacity(0.6))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(qaState.isSyncEnabled ? Color.green.opacity(0.15) : Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle synchronized scroll & click across all devices")

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Zoom Controls
            HStack(spacing: 5) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        qaState.gridScale = max(0.4, qaState.gridScale - 0.15)
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                Text("\(Int(qaState.gridScale * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(minWidth: 38)

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        qaState.gridScale = min(1.2, qaState.gridScale + 0.15)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())

                // Quick zoom presets
                HStack(spacing: 2) {
                    ForEach([0.5, 0.75, 1.0], id: \.self) { targetScale in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                qaState.gridScale = targetScale
                            }
                        } label: {
                            Text("\(Int(targetScale * 100))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(abs(qaState.gridScale - targetScale) < 0.05 ? Color.accentColor : .white.opacity(0.5))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(abs(qaState.gridScale - targetScale) < 0.05 ? Color.accentColor.opacity(0.2) : Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Screenshot button
            Button {
                onScreenshot()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Capture Screenshot")

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Exit Multi-Device Grid
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    qaState.isMultiDeviceActive = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Exit Multi-Device Grid")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.94))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
    }

    @ViewBuilder
    private func deviceCard(for preset: ViewportPreset) -> some View {
        let isLandscape = orientationOverrides[preset] ?? qaState.isLandscape
        let dims = qaState.dimensions(for: preset, landscape: isLandscape) ?? CGSize(width: 375, height: 667)
        let scale = qaState.gridScale
        let scaledWidth = dims.width * scale
        let scaledHeight = dims.height * scale

        VStack(spacing: 8) {
            // Header strip
            HStack(spacing: 6) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                Text(preset.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(Int(dims.width)) × \(Int(dims.height))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                // Reload button
                Button {
                    reloadTokens[preset] = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Reload this device")

                // Rotate orientation
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        orientationOverrides[preset] = !isLandscape
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isLandscape ? Color.accentColor : .white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Rotate device")

                // Remove device from grid
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        qaState.removeMultiDevicePreset(preset)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove from grid")
            }
            .padding(.horizontal, 8)
            .frame(width: max(scaledWidth, 180))

            // Device Frame with isolated web content
            ZStack(alignment: .topLeading) {
                MultiDeviceWebViewHost(
                    url: tab.currentPageURL ?? tab.url,
                    preset: preset,
                    spaceID: tab.container.id,
                    engineKind: tab.container.engineKind,
                    reloadTrigger: reloadTokens[preset] ?? UUID()
                )
                .frame(width: dims.width, height: dims.height)
                .scaleEffect(scale, anchor: .topLeading)
            }
            .frame(width: scaledWidth, height: scaledHeight)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
    }

    private var addDeviceCard: some View {
        let scale = qaState.gridScale
        let cardHeight = max(240 * scale, 200)

        return Menu {
            ForEach(ViewportPreset.allCases.filter { $0 != .default && !qaState.multiDevicePresets.contains($0) }) { preset in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        qaState.addMultiDevicePreset(preset)
                    }
                } label: {
                    Label(preset.label, systemImage: preset.iconName)
                }
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.white.opacity(0.5))
                Text("Add Viewport")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 160 * scale, height: cardHeight)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
}

// MARK: - MultiDeviceWebViewHost
struct MultiDeviceWebViewHost: NSViewRepresentable {
    let url: URL
    let preset: ViewportPreset
    let spaceID: UUID
    let engineKind: BrowserEngineKind
    let reloadTrigger: UUID

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let id = UUID()
        var currentURL: URL?
        var lastReloadTrigger: UUID?
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

        let syncScript = WKUserScript(
            source: DeviceSyncBridge.injectionScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(syncScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        context.coordinator.currentURL = url
        context.coordinator.lastReloadTrigger = reloadTrigger
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        let ua: String = switch preset {
        case .mobileS, .mobileM, .mobileL:
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
        case .tablet:
            "Mozilla/5.0 (iPad; CPU OS 18_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Mobile/15E148 Safari/604.1"
        default:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        }
        webView.customUserAgent = ua
        webView.load(URLRequest(url: url))

        DeviceSyncBridge.shared.register(id: context.coordinator.id, peer: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastReloadTrigger != reloadTrigger {
            context.coordinator.lastReloadTrigger = reloadTrigger
            nsView.reload()
            return
        }

        if let current = context.coordinator.currentURL, current != url {
            context.coordinator.currentURL = url
            nsView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        DeviceSyncBridge.shared.unregister(id: coordinator.id)
        nsView.stopLoading()
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: DeviceSyncBridge.messageName)
    }
}
