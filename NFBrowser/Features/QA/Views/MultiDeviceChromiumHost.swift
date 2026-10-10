import SwiftUI

/// Device pane for Chromium Spaces, in the Space's Chromium profile. Chromium emulates
/// the device through the DevTools protocol: the CSS viewport scaled to the grid's
/// size, and for phones and tablets mobile layout rules, touch and Chrome for
/// Android's user agent.
struct MultiDeviceChromiumHost: NSViewRepresentable {
    let url: URL
    let preset: ViewportPreset
    let viewport: CGSize
    let scale: CGFloat
    let spaceID: UUID
    /// Changes when the user reloads the device; nil until then.
    let reloadTrigger: UUID?

    final class Coordinator: NSObject, NFChromiumBrowserViewDelegate {
        let id = UUID()
        var currentURL: URL?
        var lastReloadTrigger: UUID?
        var viewport: CGSize = .zero
        var scale: CGFloat = 1

        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            didReceiveDevToolsEvent method: String,
            params: [String: Any]
        ) {
            DeviceSyncBridge.shared.handleChromiumEvent(method: method, params: params, from: view)
        }

        /// Links that would open a tab stay in the device pane.
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
        let view = NFChromiumBrowserView.makePane(
            profileIdentifier: spaceID.uuidString,
            persistent: true,
            url: url,
            setup: DeviceSyncBridge.chromiumSetup + Self.deviceEmulation(for: preset)
                + [Self.metrics(for: preset, viewport: viewport, scale: scale)]
        )
        view.delegate = context.coordinator
        view.observedDevToolsEvents = ["Runtime.bindingCalled"]
        context.coordinator.currentURL = url
        context.coordinator.lastReloadTrigger = reloadTrigger
        context.coordinator.viewport = viewport
        context.coordinator.scale = scale
        DeviceSyncBridge.shared.register(id: context.coordinator.id, peer: view)
        return view
    }

    func updateNSView(_ view: NFChromiumBrowserView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.viewport != viewport || coordinator.scale != scale {
            coordinator.viewport = viewport
            coordinator.scale = scale
            let metrics = Self.metrics(for: preset, viewport: viewport, scale: scale)
            view.sendDevToolsMethod(metrics.method, params: metrics.params, completion: nil)
        }
        if coordinator.lastReloadTrigger != reloadTrigger {
            coordinator.lastReloadTrigger = reloadTrigger
            view.reload()
            return
        }
        if let current = coordinator.currentURL, current != url {
            coordinator.currentURL = url
            view.load(url)
        }
    }

    static func dismantleNSView(_ view: NFChromiumBrowserView, coordinator: Coordinator) {
        DeviceSyncBridge.shared.unregister(id: coordinator.id)
        view.closeBrowser()
    }

    private static func isHandheld(_ preset: ViewportPreset) -> Bool {
        [.mobileS, .mobileM, .mobileL, .tablet].contains(preset)
    }

    /// The device's CSS viewport, which Chromium scales to the size the grid shows. The
    /// pane already has that size: letting Chromium resize its view as well crashes CEF
    /// before the page has a renderer.
    private static func metrics(for preset: ViewportPreset, viewport: CGSize, scale: CGFloat)
        -> ChromiumDevToolsCommand
    {
        ChromiumDevToolsCommand(
            method: "Emulation.setDeviceMetricsOverride",
            params: [
                "width": Int(viewport.width),
                "height": Int(viewport.height),
                "deviceScaleFactor": 0,
                "mobile": isHandheld(preset),
                "scale": scale,
                "dontSetVisibleSize": true
            ]
        )
    }

    /// Touch input and Chrome for Android's reduced user agent (its OS version and model
    /// are frozen), with client hints that agree with it.
    private static func deviceEmulation(for preset: ViewportPreset) -> [ChromiumDevToolsCommand] {
        guard isHandheld(preset) else { return [] }
        let isPhone = preset != .tablet
        let major = NFChromiumRuntime.shared.chromiumVersion.split(separator: ".").first.map(String.init) ?? "0"
        let userAgent = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) "
            + "Chrome/\(major).0.0.0 \(isPhone ? "Mobile " : "")Safari/537.36"
        let clientHints: [String: Any] = [
            "brands": [["brand": "Chromium", "version": major], ["brand": "Not=A?Brand", "version": "24"]],
            "platform": "Android",
            "platformVersion": "",
            "architecture": "",
            "model": "",
            "mobile": isPhone
        ]
        return [
            ChromiumDevToolsCommand(
                method: "Emulation.setTouchEmulationEnabled",
                params: ["enabled": true, "maxTouchPoints": 5]
            ),
            ChromiumDevToolsCommand(
                method: "Emulation.setUserAgentOverride",
                params: ["userAgent": userAgent, "platform": "Linux armv8l", "userAgentMetadata": clientHints]
            )
        ]
    }
}
