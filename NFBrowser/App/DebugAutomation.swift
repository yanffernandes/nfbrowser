#if DEBUG
    import Foundation

    /// Debug-only launch options for driving a real browser window from scripts,
    /// used to verify engines end to end without touching the UI:
    /// - `--debug-space-engine <webkit|chromium>` switches the active Space's engine.
    /// - `--debug-cross-engine` opens Cross-Engine Compare on the first loaded page.
    /// - `--debug-agent-bridge <file>` starts the agent browser bridge and writes the
    ///   environment for the bundled nf-browser CLI (endpoint and token) to `file`.
    enum DebugAutomation {
        private static var didRun = false

        @MainActor
        static func run(tabManager: TabManager, agentTerminal: BrowserAgentTerminalManager) {
            guard !didRun else { return }
            didRun = true
            let arguments = CommandLine.arguments

            if let rawEngine = value(after: "--debug-space-engine", in: arguments),
               let engine = BrowserEngineKind(rawValue: rawEngine),
               let container = tabManager.activeContainer,
               container.engineKind != engine
            {
                container.engineKind = engine
                try? tabManager.modelContext.save()
                tabManager.rebuildLoadedPages(for: container.id)
            }

            if arguments.contains("--debug-cross-engine") {
                // Opens Cross-Engine Compare once the first page has finished loading.
                Task { @MainActor in
                    while tabManager.activeTab == nil || tabManager.activeTab?.isLoading == true {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    tabManager.activeTab?.qaState.toggleCrossEngine()
                }
            }

            if let path = value(after: "--debug-agent-bridge", in: arguments) {
                let bridge = agentTerminal.browserBridge
                Task { @MainActor in
                    // environmentValues() is the whole process environment; only the
                    // bridge endpoint and token belong in the file, readable by the owner.
                    var values: [String: String]
                    do {
                        try await bridge.start()
                        values = bridge.environmentValues().filter { key, _ in
                            key.hasPrefix("NF_BROWSER_") || key.hasPrefix("ORA_BROWSER_")
                        }
                    } catch {
                        values = ["error": error.localizedDescription]
                    }
                    let data = (try? JSONSerialization.data(withJSONObject: values)) ?? Data()
                    FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600])
                }
            }
        }

        private static func value(after flag: String, in arguments: [String]) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }
    }
#endif
