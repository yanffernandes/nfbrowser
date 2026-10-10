#if DEBUG
    import AppKit

    /// Smoke-test phase for the app-facing ChromiumBrowserPage: navigation events, the
    /// script bridge that replaces window.webkit, and JS dialogs routed to the app.
    final class ChromiumPageSmokeCheck: BrowserPageDelegate {
        private var phases: [BrowserNavigationPhase] = []
        private var messages: [BrowserScriptMessage] = []
        private var alerts: [String] = []

        @MainActor
        func run(hostedIn stack: NSStackView) async -> (report: [String: Any], checks: [String: Bool]) {
            let probe = BrowserUserScript(
                name: "probe",
                source: "window.__oraBridge && window.__oraBridge.postMessage('linkHover', 'bridge-ok');",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            let engine = BrowserEngine.shared
            let page = engine.makePage(
                engineKind: .chromium,
                profile: engine.makeProfile(engineKind: .chromium, identifier: UUID(), isPrivate: true),
                configuration: .oraDefault(engineKind: .chromium, userScripts: [probe], privacySettings: .init()),
                delegate: self
            )
            stack.addArrangedSubview(page.contentView)
            defer { page.teardown() }

            guard let url = URL(string: "https://example.com/") else { return ([:], [:]) }
            page.load(URLRequest(url: url))
            let finished = await waitUntil { self.phases.contains(.finished) }
            let bridged = await waitUntil(timeout: 10) {
                self.messages.contains { $0.name == "linkHover" && $0.body as? String == "bridge-ok" }
            }
            let globals = await evaluate(
                page,
                """
                ({webkit: typeof window.webkit,
                  bindings: Object.getOwnPropertyNames(window).filter(name => name.startsWith('__nf')).length,
                  bridge: typeof window.__oraBridge})
                """
            )
            page.evaluateJavaScript("setTimeout(() => alert('hello-from-page'), 0); 'scheduled'")
            let alerted = await waitUntil(timeout: 10) { self.alerts.contains("hello-from-page") }

            let background = await checkBackgroundLoad(hostedIn: stack, engine: engine)
            let trackerFetch = "fetch('https://www.google-analytics.com/analytics.js', {mode: 'no-cors'})"
                + ".then(() => 'loaded', () => 'blocked')"
            let withProtection = await fetchResult(trackerFetch, blockTrackers: true, hostedIn: stack, engine: engine)
            let withoutProtection = await fetchResult(
                trackerFetch,
                blockTrackers: false,
                hostedIn: stack,
                engine: engine
            )

            let report: [String: Any] = [
                "background_tab": background,
                "tracker_fetch": ["protected": withProtection, "unprotected": withoutProtection],
                "phases": phases.map { "\($0)" },
                "messages": messages.map(\.name),
                "globals": globals,
                "alerts": alerts
            ]
            let checks = [
                "page_navigation_events": finished && phases.contains(.started),
                "page_script_bridge": bridged,
                "page_hides_engine_globals": globals["webkit"] as? String == "undefined"
                    && globals["bindings"] as? Int == 0 && globals["bridge"] as? String == "object",
                "page_js_dialog": alerted,
                "page_loads_in_background": background["loaded_before_shown"] as? Bool == true,
                "page_moves_into_window": background["works_after_shown"] as? Bool == true,
                "tracker_protection": withProtection == "blocked" && withoutProtection == "loaded"
            ]
            return (report, checks)
        }

        /// A tab opened in the background loads before it is shown, then keeps working
        /// once the app moves its view into a window.
        @MainActor
        private func checkBackgroundLoad(hostedIn stack: NSStackView, engine: BrowserEngine) async -> [String: Any] {
            let watcher = ChromiumPageSmokeCheck()
            let page = engine.makePage(
                engineKind: .chromium,
                profile: engine.makeProfile(engineKind: .chromium, identifier: UUID(), isPrivate: true),
                configuration: .oraDefault(engineKind: .chromium, userScripts: [], privacySettings: .init()),
                delegate: watcher
            )
            defer { page.teardown() }
            guard let url = URL(string: "https://example.com/?background") else { return [:] }
            page.load(URLRequest(url: url))
            let loaded = await waitUntil { watcher.phases.contains(.finished) }
            let wasParked = page.contentView.window != nil && page.contentView.window !== stack.window

            stack.addArrangedSubview(page.contentView)
            let title = await evaluate(page, "({title: document.title})")["title"] as? String
            return [
                "loaded_before_shown": loaded && wasParked,
                "works_after_shown": page.contentView.window === stack.window && title == "Example Domain"
            ]
        }

        /// Runs a fetch on example.com in a page whose Space has tracker protection on or off.
        @MainActor
        private func fetchResult(
            _ script: String,
            blockTrackers: Bool,
            hostedIn stack: NSStackView,
            engine: BrowserEngine
        ) async -> String {
            let watcher = ChromiumPageSmokeCheck()
            let page = engine.makePage(
                engineKind: .chromium,
                profile: engine.makeProfile(engineKind: .chromium, identifier: UUID(), isPrivate: true),
                configuration: .oraDefault(
                    engineKind: .chromium,
                    userScripts: [],
                    privacySettings: SpacePrivacySettings(blockThirdPartyTrackers: blockTrackers)
                ),
                delegate: watcher
            )
            defer { page.teardown() }
            guard let url = URL(string: "https://example.com/?trackers") else { return "" }
            stack.addArrangedSubview(page.contentView)
            page.load(URLRequest(url: url))
            _ = await waitUntil { watcher.phases.contains(.finished) }
            var result: Any?
            page.evaluateJavaScript(script) { value, _ in result = value ?? "" }
            _ = await waitUntil(timeout: 15) { result != nil }
            return result as? String ?? ""
        }

        @MainActor
        private func waitUntil(timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition() {
                if Date() > deadline {
                    return false
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return true
        }

        @MainActor
        private func evaluate(_ page: BrowserPage, _ script: String) async -> [String: Any] {
            var result: [String: Any]?
            page.evaluateJavaScript(script) { value, _ in
                result = value as? [String: Any] ?? [:]
            }
            _ = await waitUntil(timeout: 10) { result != nil }
            return result ?? [:]
        }

        // MARK: - BrowserPageDelegate

        func browserPage(_ page: BrowserPage, didUpdateNavigation event: BrowserNavigationEvent) {
            phases.append(event.phase)
        }

        func browserPage(_ page: BrowserPage, didReceiveScriptMessage message: BrowserScriptMessage) {
            messages.append(message)
        }

        func browserPage(_ page: BrowserPage, runJavaScriptAlert message: String) {
            alerts.append(message)
        }
    }
#endif
