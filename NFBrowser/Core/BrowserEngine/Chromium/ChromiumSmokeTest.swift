#if DEBUG
    import AppKit

    /// Debug-only end-to-end check of the Chromium engine. Run
    /// `NFBrowser.app/Contents/MacOS/NFBrowser --chromium-smoke-test <output-dir>`;
    /// it writes report.json and a screenshot to the directory, then exits
    /// (status 0 when every check passed).
    final class ChromiumSmokeTest: NSObject, NFChromiumBrowserViewDelegate {
        private static var current: ChromiumSmokeTest?

        static func runIfRequested() {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "--chromium-smoke-test") else { return }
            let outputPath = arguments.indices.contains(index + 1)
                ? arguments[index + 1]
                : NSTemporaryDirectory() + "nfbrowser-chromium-smoke"
            let test = ChromiumSmokeTest(outputDirectory: URL(fileURLWithPath: outputPath))
            current = test
            Task { @MainActor in await test.run() }
        }

        private let outputDirectory: URL
        private let runID = UUID().uuidString.prefix(8)
        private var report: [String: Any] = [:]
        private var checks: [String: Bool] = [:]
        private var finishedLoads: [ObjectIdentifier: Int] = [:]
        private var bindingPayloads: [String] = []
        private var downloadStates: [String] = []
        private var completedDownload: URL?
        private var window: NSWindow?
        private var isFinished = false

        init(outputDirectory: URL) {
            self.outputDirectory = outputDirectory
        }

        // MARK: - Scenario

        @MainActor
        private func run() async {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let watchdog = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180 * 1_000_000_000)
                self?.finish(failure: "timeout")
            }
            defer { watchdog.cancel() }

            guard startRuntime(), let start = URL(string: "https://example.com/") else { return }
            let viewA = makeView(profile: "smoke-a-\(runID)", persistent: true, url: start)
            let viewB = makeView(profile: "smoke-b-\(runID)", persistent: true, url: start)
            let viewC = makeView(profile: "smoke-private-\(runID)", persistent: false, url: start)
            let viewA2 = makeView(profile: "smoke-a-\(runID)", persistent: true, url: nil)
            showWindow(with: [viewA, viewB, viewC, viewA2])

            let loadStart = Date()
            guard await waitForLoads([viewA, viewB, viewC], count: 1) else {
                finish(failure: "initial load")
                return
            }
            report["first_load_ms"] = milliseconds(since: loadStart)
            report["page_facts"] = await evaluate(viewA, Self.pageFactsScript)

            await checkProfileIsolation(viewA, secondTab: viewA2, otherProfile: viewB, ephemeral: viewC, url: start)
            await checkBackNavigation(viewA)
            await checkDevToolsBridge(viewA)
            checks["screenshot"] = await saveScreenshot(of: viewA)
            await checkPopupKeepsOpener(viewA)
            await checkCookieImportAndClear()
            await checkDownload(viewA)
            if let stack = window?.contentView as? NSStackView {
                let pageCheck = await ChromiumPageSmokeCheck().run(hostedIn: stack)
                report["chromium_page"] = pageCheck.report
                checks.merge(pageCheck.checks) { $1 }
            }
            recordResourceUsage()
            finish(failure: nil)
        }

        private func startRuntime() -> Bool {
            let runtime = NFChromiumRuntime.shared
            let initStart = Date()
            do {
                try runtime.startIfNeeded()
            } catch {
                finish(failure: "init: \(error.localizedDescription)")
                return false
            }
            report["init_ms"] = milliseconds(since: initStart)
            report["cef_version"] = runtime.cefVersion
            report["chromium_version"] = runtime.chromiumVersion
            return true
        }

        @MainActor
        private func checkProfileIsolation(
            _ view: NFChromiumBrowserView,
            secondTab: NFChromiumBrowserView,
            otherProfile: NFChromiumBrowserView,
            ephemeral: NFChromiumBrowserView,
            url: URL
        ) async {
            _ = await evaluate(
                view,
                "document.cookie = 'nf_probe=A; path=/; max-age=3600'; localStorage.setItem('nf_probe', 'A'); 'set'"
            )
            secondTab.load(url)
            _ = await waitForLoads([secondTab], count: 1)
            let probe = "({cookie: document.cookie, storage: localStorage.getItem('nf_probe')})"
            let isolation: [String: Any] = await [
                "A": evaluate(view, probe),
                "A_second_tab": evaluate(secondTab, probe),
                "B": evaluate(otherProfile, probe),
                "private": evaluate(ephemeral, probe)
            ]
            report["isolation"] = isolation
            checks["same_profile_shares_storage"] = hasProbe(isolation["A_second_tab"])
            checks["profiles_are_isolated"] = hasProbe(isolation["A"]) && !hasProbe(isolation["B"])
                && !hasProbe(isolation["private"])
        }

        @MainActor
        private func checkBackNavigation(_ view: NFChromiumBrowserView) async {
            guard let next = URL(string: "https://www.iana.org/help/example-domains") else { return }
            view.load(next)
            _ = await waitForLoads([view], count: 2)
            view.goBack()
            let wentBack = await waitUntil { view.currentURL?.host == "example.com" }
            report["navigation"] = [
                "after_back": view.currentURL?.absoluteString ?? "",
                "can_go_forward": view.canGoForward,
                "title": view.title ?? ""
            ]
            checks["back_navigation"] = wentBack && view.canGoForward
        }

        @MainActor
        private func checkDevToolsBridge(_ view: NFChromiumBrowserView) async {
            _ = await devTools(view, "Runtime.addBinding", ["name": "nfSmokeBinding"])
            _ = await evaluate(view, "nfSmokeBinding('hello-from-page'); 'sent'")
            checks["devtools_binding"] = await waitUntil(timeout: 10) {
                self.bindingPayloads.contains("hello-from-page")
            }

            _ = await devTools(view, "Page.enable", [:])
            _ = await devTools(view, "Page.addScriptToEvaluateOnNewDocument", ["source": "window.__nfInjected = 42;"])
            let loadsBeforeReload = finishedLoads[ObjectIdentifier(view)] ?? 0
            view.reload()
            _ = await waitForLoads([view], count: loadsBeforeReload + 1)
            let injected = await evaluate(view, "window.__nfInjected")
            report["injected_value"] = injected
            checks["document_start_script"] = (injected as? Int) == 42
        }

        @MainActor
        private func checkDownload(_ view: NFChromiumBrowserView) async {
            _ = await evaluate(view, Self.downloadScript)
            let downloaded = await waitUntil(timeout: 20) { self.completedDownload != nil }
            let content = completedDownload.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            report["download"] = [
                "file": completedDownload?.path ?? "",
                "content": content ?? "",
                "states": downloadStates
            ]
            checks["download"] = downloaded && content == "nfbrowser chromium download"
        }

        private func recordResourceUsage() {
            report["memory_mb"] = processMemoryMegabytes()
            report["bundle_mb"] = directoryMegabytes(Bundle.main.bundlePath)
            if let frameworks = Bundle.main.privateFrameworksPath {
                let framework = frameworks + "/Chromium Embedded Framework.framework/Versions/A"
                report["framework_mb"] = directoryMegabytes(framework)
            }
        }

        // MARK: - Helpers

        private func makeView(profile: String, persistent: Bool, url: URL?) -> NFChromiumBrowserView {
            let view = NFChromiumBrowserView(
                frame: NSRect(x: 0, y: 0, width: 400, height: 800),
                profileIdentifier: profile,
                persistent: persistent,
                initialURL: url
            )
            view.delegate = self
            return view
        }

        private func showWindow(with views: [NSView]) {
            let stack = NSStackView(views: views)
            stack.orientation = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 2
            let window = NSWindow(
                contentRect: NSRect(x: 60, y: 60, width: 1600, height: 820),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Chromium smoke test"
            window.isReleasedWhenClosed = false
            window.contentView = stack
            window.makeKeyAndOrderFront(nil)
            self.window = window
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
        private func waitForLoads(_ views: [NFChromiumBrowserView], count: Int) async -> Bool {
            await waitUntil {
                views.allSatisfy { (self.finishedLoads[ObjectIdentifier($0)] ?? 0) >= count }
            }
        }

        @MainActor
        private func evaluate(_ view: NFChromiumBrowserView, _ script: String) async -> Any {
            await withCheckedContinuation { continuation in
                view.evaluateJavaScript(script) { result, error in
                    if let error {
                        continuation.resume(returning: "error: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: result ?? NSNull())
                    }
                }
            }
        }

        @MainActor
        private func devTools(
            _ view: NFChromiumBrowserView,
            _ method: String,
            _ params: [String: Any]
        ) async -> [String: Any] {
            await withCheckedContinuation { continuation in
                view.sendDevToolsMethod(method, params: params) { result, error in
                    continuation.resume(returning: result ?? ["error": error?.localizedDescription ?? "unknown"])
                }
            }
        }

        @MainActor
        private func saveScreenshot(of view: NFChromiumBrowserView) async -> Bool {
            let image: NSImage? = await withCheckedContinuation { continuation in
                view.captureScreenshot { image, _ in continuation.resume(returning: image) }
            }
            guard let tiff = image?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return false }
            let url = outputDirectory.appendingPathComponent("screenshot-a.png")
            report["screenshot"] = url.path
            return (try? png.write(to: url)) != nil
        }

        private func finish(failure: String?) {
            guard !isFinished else { return }
            isFinished = true
            let failedChecks = checks.filter { !$0.value }.map(\.key).sorted()
            report["checks"] = checks
            report["status"] = failure == nil && failedChecks.isEmpty ? "passed" : "failed"
            if let failure {
                report["failure"] = failure
            }
            if let data = try? JSONSerialization.data(
                withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys]
            ) {
                try? data.write(to: outputDirectory.appendingPathComponent("report.json"))
            }
            NFChromiumRuntime.shared.shutdown()
            let root = NFChromiumRuntime.shared.rootCacheURL
            for name in ["smoke-a-\(runID)", "smoke-b-\(runID)"] {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
            }
            exit(report["status"] as? String == "passed" ? 0 : 1)
        }

        // MARK: - NFChromiumBrowserViewDelegate

        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            didFinishNavigationTo url: URL?,
            httpStatusCode: Int
        ) {
            finishedLoads[ObjectIdentifier(view), default: 0] += 1
        }

        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            didReceiveDevToolsEvent method: String,
            params: [String: Any]
        ) {
            if method == "Runtime.bindingCalled", let payload = params["payload"] as? String {
                bindingPayloads.append(payload)
            }
        }

        func chromiumBrowserView(
            _ view: NFChromiumBrowserView,
            decideDestinationFor download: NFChromiumDownload,
            completion: @escaping (URL?) -> Void
        ) {
            completion(outputDirectory.appendingPathComponent(download.suggestedFileName))
        }

        func chromiumBrowserView(_ view: NFChromiumBrowserView, downloadDidUpdate download: NFChromiumDownload) {
            downloadStates.append("\(download.receivedBytes)/\(download.totalBytes) complete=\(download.isComplete)")
            if download.isComplete {
                completedDownload = download.destinationURL
            }
        }
    }

    private extension ChromiumSmokeTest {
        /// Cookies imported into a Chromium Space reach its pages, and clearing a site's
        /// cookies removes them.
        @MainActor
        func checkCookieImportAndClear() async {
            guard let stack = window?.contentView as? NSStackView,
                  let url = URL(string: "https://example.com/"),
                  let cookie = HTTPCookie(properties: [
                      .domain: ".example.com",
                      .path: "/",
                      .name: "nf_imported",
                      .value: "1",
                      .secure: "TRUE",
                      .expires: Date().addingTimeInterval(3600)
                  ])
            else { return }
            let spaceID = UUID()
            let profile = BrowserEngineProfile(engineKind: .chromium, identifier: spaceID, isPrivate: false)
            let imported = await profile.importCookies([cookie])

            let view = makeView(profile: spaceID.uuidString, persistent: true, url: url)
            stack.addArrangedSubview(view)
            _ = await waitForLoads([view], count: 1)
            let visible = await evaluate(view, "document.cookie") as? String ?? ""

            await withCheckedContinuation { continuation in
                profile.clearData(ofTypes: [.cookies], forHost: "www.example.com") { continuation.resume() }
            }
            view.reload()
            _ = await waitForLoads([view], count: 2)
            let afterClear = await evaluate(view, "document.cookie") as? String ?? ""
            view.closeBrowser()
            NFChromiumRuntime.shared.removeProfile(spaceID.uuidString)

            report["cookies"] = ["imported": imported, "visible": visible, "after_clear": afterClear]
            checks["cookie_import"] = imported == 1 && visible.contains("nf_imported=1")
            checks["cookie_clear_for_host"] = !afterClear.contains("nf_imported")
        }

        /// window.open() with window features must open a real popup that keeps
        /// window.opener, which OAuth sign-in flows depend on.
        @MainActor
        func checkPopupKeepsOpener(_ view: NFChromiumBrowserView) async {
            let browsersBefore = NFChromiumRuntime.shared.liveBrowserCount
            _ = await evaluate(
                view,
                "window.__nfPopup = window.open(location.href, 'nfpopup', 'width=420,height=320'); 'ok'"
            )
            let opened = await waitUntil(timeout: 10) { NFChromiumRuntime.shared.liveBrowserCount > browsersBefore }
            let probe = """
            (() => {
              const popup = window.__nfPopup;
              return !!popup && !popup.closed && popup.document.readyState === 'complete' && popup.opener === window;
            })()
            """
            var linked = false
            for _ in 0 ..< 30 where !linked {
                linked = await evaluate(view, probe) as? Bool == true
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            _ = await evaluate(view, "window.__nfPopup && window.__nfPopup.close(); 'closed'")
            var closedForPage = false
            for _ in 0 ..< 20 where !closedForPage {
                closedForPage = await evaluate(view, "!window.__nfPopup || window.__nfPopup.closed") as? Bool == true
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let released = await waitUntil(timeout: 10) { NFChromiumRuntime.shared.liveBrowserCount == browsersBefore }
            report["popup"] = [
                "opened": opened,
                "linked_to_opener": linked,
                "closed_for_page": closedForPage,
                "browser_released": released,
                "live_browsers": NFChromiumRuntime.shared.liveBrowserCount,
                "popup_windows": NSApp.windows.filter(\.isVisible).map(\.title)
            ]
            checks["popup_keeps_opener"] = opened && linked && closedForPage
        }

        static let pageFactsScript = """
        ({
          userAgent: navigator.userAgent,
          brands: navigator.userAgentData ? navigator.userAgentData.brands.map(b => b.brand + ' ' + b.version) : [],
          h264: MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"'),
          aac: MediaSource.isTypeSupported('audio/mp4; codecs="mp4a.40.2"'),
          vp9: MediaSource.isTypeSupported('video/webm; codecs="vp9"'),
          av1: MediaSource.isTypeSupported('video/mp4; codecs="av01.0.05M.08"'),
          opus: MediaSource.isTypeSupported('audio/webm; codecs="opus"'),
          webkitMessageHandlers: typeof window.webkit !== 'undefined',
          safariGlobal: typeof window.safari !== 'undefined'
        })
        """

        static let downloadScript = """
        (() => {
          const link = document.createElement('a');
          link.href = URL.createObjectURL(new Blob(['nfbrowser chromium download'], {type: 'text/plain'}));
          link.download = 'nf-smoke.txt';
          document.body.appendChild(link);
          link.click();
          return 'clicked';
        })()
        """

        func hasProbe(_ value: Any?) -> Bool {
            guard let probe = value as? [String: Any] else { return false }
            let cookie = probe["cookie"] as? String ?? ""
            return cookie.contains("nf_probe=A") && probe["storage"] as? String == "A"
        }

        func milliseconds(since date: Date) -> Int {
            Int(Date().timeIntervalSince(date) * 1000)
        }

        func processMemoryMegabytes() -> [String: Int] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/ps")
            process.arguments = ["-axo", "rss=,comm="]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()
            let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            var app = 0
            var helpers = 0
            for line in output.split(separator: "\n") {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let rss = Int(parts[0]),
                      parts[1].hasPrefix(Bundle.main.bundlePath) else { continue }
                if parts[1].contains("NFBrowser Helper") {
                    helpers += rss
                } else {
                    app += rss
                }
            }
            return ["app": app / 1024, "helpers": helpers / 1024, "total": (app + helpers) / 1024]
        }

        func directoryMegabytes(_ path: String) -> Int {
            let enumerator = FileManager.default.enumerator(atPath: path)
            var bytes = 0
            while let item = enumerator?.nextObject() as? String {
                let attributes = try? FileManager.default.attributesOfItem(atPath: path + "/" + item)
                if attributes?[.type] as? FileAttributeType == .typeRegular {
                    bytes += (attributes?[.size] as? Int) ?? 0
                }
            }
            return bytes / 1_048_576
        }
    }
#endif
