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

            let report: [String: Any] = [
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
                "page_js_dialog": alerted
            ]
            return (report, checks)
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
