#if DEBUG
    import AppKit

    /// Smoke-test phase for the app-facing ChromiumBrowserPage: navigation events, the
    /// script bridge that replaces window.webkit, JS dialogs routed to the app, loading in
    /// the background and the Space privacy settings.
    final class ChromiumPageSmokeCheck: BrowserPageDelegate {
        private var phases: [BrowserNavigationPhase] = []
        private var messages: [BrowserScriptMessage] = []
        private var alerts: [String] = []

        @MainActor
        func run(hostedIn stack: NSStackView) async -> (report: [String: Any], checks: [String: Bool]) {
            var (report, checks) = await checkPage(hostedIn: stack)
            let background = await checkBackgroundLoad(hostedIn: stack)
            report["background_tab"] = background
            checks["page_loads_in_background"] = background["loaded_before_shown"] as? Bool == true
            checks["page_moves_into_window"] = background["works_after_shown"] as? Bool == true
            let privacy = await checkPrivacy(hostedIn: stack)
            report["privacy"] = privacy.report
            checks.merge(privacy.checks) { $1 }
            return (report, checks)
        }

        /// Navigation events, the script bridge and JS dialogs on one page.
        @MainActor
        private func checkPage(hostedIn stack: NSStackView) async -> (report: [String: Any], checks: [String: Bool]) {
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

        /// A tab opened in the background loads before it is shown, then keeps working
        /// once the app moves its view into a window.
        @MainActor
        private func checkBackgroundLoad(hostedIn stack: NSStackView) async -> [String: Any] {
            let engine = BrowserEngine.shared
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

        /// Tracker protection and the three cookie policies, in private and persistent
        /// profiles. Third-party cookies are probed from a cross-site frame served locally.
        @MainActor
        private func checkPrivacy(hostedIn stack: NSStackView) async
            -> (report: [String: Any], checks: [String: Bool])
        {
            let tracker = "fetch('https://www.google-analytics.com/analytics.js', {mode: 'no-cors'})"
                + ".then(() => 'loaded', () => 'blocked')"
            let protected = await probe(tracker, .init(blockThirdPartyTrackers: true), hostedIn: stack)
            let unprotected = await probe(tracker, .init(blockThirdPartyTrackers: false), hostedIn: stack)

            let firstParty = "document.cookie = 'nf=1'; document.cookie"
            let allowed = await probe(firstParty, .init(cookiesPolicy: .allowAll), hostedIn: stack)
            let blockedPrivate = await probe(firstParty, .init(cookiesPolicy: .blockAll), hostedIn: stack)
            let blockedPersistent = await probe(
                firstParty,
                .init(cookiesPolicy: .blockAll),
                persistent: true,
                hostedIn: stack
            )

            let server = ChromiumSmokeServer()
            server?.start()
            defer { server?.stop() }
            _ = await waitUntil(timeout: 5) { server?.topURL != nil }
            let frameCookies = "new Promise(resolve => { const poll = () => window.frameCookies"
                + " ? resolve(window.frameCookies) : setTimeout(poll, 50); poll(); })"
            var thirdParty: [String: String] = [:]
            for policy in CookiesPolicy.allCases {
                thirdParty[policy.rawValue] = await probe(
                    frameCookies,
                    .init(cookiesPolicy: policy),
                    url: server?.topURL,
                    hostedIn: stack
                )
            }

            let report: [String: Any] = [
                "tracker_fetch": ["protected": protected, "unprotected": unprotected],
                "first_party_cookie": [
                    "allow_all": allowed,
                    "block_all_private": blockedPrivate,
                    "block_all_persistent": blockedPersistent
                ],
                "third_party_frame_cookie": thirdParty
            ]
            let checks = [
                "tracker_protection": protected == "blocked" && unprotected == "loaded",
                "cookies_block_all": allowed == "nf=1" && blockedPrivate.isEmpty && blockedPersistent.isEmpty,
                "cookies_block_third_party": thirdParty[CookiesPolicy.allowAll.rawValue] == "stored"
                    && thirdParty[CookiesPolicy.blockThirdParty.rawValue] == "blocked"
                    && thirdParty[CookiesPolicy.blockAll.rawValue] == "blocked"
            ]
            return (report, checks)
        }

        /// Opens `url` in a new page with the given Space privacy settings and returns the
        /// string `script` evaluates to there.
        @MainActor
        private func probe(
            _ script: String,
            _ settings: SpacePrivacySettings,
            url: URL? = URL(string: "https://example.com/?privacy"),
            persistent: Bool = false,
            hostedIn stack: NSStackView
        ) async -> String {
            guard let url else { return "" }
            let engine = BrowserEngine.shared
            let profile = engine.makeProfile(engineKind: .chromium, identifier: UUID(), isPrivate: !persistent)
            let watcher = ChromiumPageSmokeCheck()
            let page = engine.makePage(
                engineKind: .chromium,
                profile: profile,
                configuration: .oraDefault(engineKind: .chromium, userScripts: [], privacySettings: settings),
                delegate: watcher
            )
            defer {
                page.teardown()
                if persistent {
                    NFChromiumRuntime.shared.removeProfile(profile.identifier.uuidString)
                }
            }
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
