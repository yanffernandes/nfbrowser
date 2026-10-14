#if DEBUG
    import AppKit
    @preconcurrency import WebKit

    /// Smoke-test phase for camera and microphone requests: they reach the app on both
    /// engines, and its answer reaches the page. WebKit grants use its stand-in devices;
    /// Chromium is only refused. Either way no camera turns on and macOS doesn't ask.
    final class MediaCaptureSmokeCheck: BrowserPageDelegate {
        private let decision: BrowserPermissionDecision
        private var requests: [String] = []

        private init(decision: BrowserPermissionDecision) {
            self.decision = decision
        }

        @MainActor
        static func run(server: ChromiumSmokeServer?, hostedIn stack: NSStackView) async
            -> (report: [String: Any], checks: [String: Bool])
        {
            let url = server?.url("/media")
            let asked = ["camera+microphone from \(MediaCapturePermissions.siteName(for: url))"]
            let webkitRefused = await capture(.webkit, decision: .deny, url: url, hostedIn: stack)
            let webkitAllowed = await capture(.webkit, decision: .grant, url: url, hostedIn: stack)
            let chromiumRefused = await capture(.chromium, decision: .deny, url: url, hostedIn: stack)

            let report: [String: Any] = [
                "webkit_refused": webkitRefused.result,
                "webkit_allowed": webkitAllowed.result,
                "chromium_refused": chromiumRefused.result,
                "requests": webkitRefused.requests + webkitAllowed.requests + chromiumRefused.requests
            ]
            let checks = [
                "media_permission_webkit": webkitRefused == ("NotAllowedError", asked)
                    && webkitAllowed == ("tracks 2", asked),
                "media_permission_chromium": chromiumRefused == ("NotAllowedError", asked)
            ]
            return (report, checks)
        }

        /// Opens `url` on a new page that answers its media requests with `decision`, and
        /// returns what the page got and what the app was asked.
        @MainActor
        private static func capture(
            _ engineKind: BrowserEngineKind,
            decision: BrowserPermissionDecision,
            url: URL?,
            hostedIn stack: NSStackView
        ) async -> (result: String, requests: [String]) {
            guard let url else { return ("", []) }
            let check = MediaCaptureSmokeCheck(decision: decision)
            let engine = BrowserEngine.shared
            let profile = engine.makeProfile(engineKind: engineKind, identifier: UUID(), isPrivate: true)
            let page: BrowserPage
            if engineKind == .webkit {
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.preferences.setValue(true, forKey: "mockCaptureDevicesEnabled")
                // WebKit holds requests until the page has focus, which a background run never gives it.
                configuration.preferences.setValue(false, forKey: "getUserMediaRequiresFocus")
                page = WebKitBrowserPage(
                    profile: profile,
                    configuration: .oraDefault(userScripts: [], privacySettings: .init()),
                    customConfiguration: configuration,
                    delegate: check
                )
            } else {
                page = engine.makePage(
                    engineKind: .chromium,
                    profile: profile,
                    configuration: .oraDefault(engineKind: .chromium, userScripts: [], privacySettings: .init()),
                    delegate: check
                )
            }
            stack.addArrangedSubview(page.contentView)
            defer { page.teardown() }
            page.load(URLRequest(url: url))

            var result = ""
            let deadline = Date().addingTimeInterval(15)
            while result.isEmpty, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
                result = await media(on: page)
            }
            return (result, check.requests)
        }

        /// The page's window.media, set by the smoke server's /media page.
        @MainActor
        private static func media(on page: BrowserPage) async -> String {
            var result: String?
            page.evaluateJavaScript("window.media || ''") { value, _ in
                result = value as? String ?? ""
            }
            let deadline = Date().addingTimeInterval(5)
            while result == nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return result ?? ""
        }

        // MARK: - BrowserPageDelegate

        func browserPage(
            _ page: BrowserPage,
            requestPermission permission: BrowserPermissionKind,
            origin: URL?,
            decisionHandler: @escaping (BrowserPermissionDecision) -> Void
        ) {
            if case let .mediaCapture(devices) = permission {
                let names = [(BrowserMediaDevices.camera, "camera"), (.microphone, "microphone"), (.screen, "screen")]
                    .filter { devices.contains($0.0) }
                    .map(\.1)
                requests.append(names.joined(separator: "+") + " from " + MediaCapturePermissions.siteName(for: origin))
            }
            decisionHandler(decision)
        }
    }
#endif
