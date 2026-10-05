import AppKit
import Foundation
import SwiftTerm
import SwiftUI

enum BrowserAgentCLI: String, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case antigravity
    case shell

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .antigravity: "Antigravity CLI"
        case .shell: "Shell"
        }
    }

    var command: String? {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .gemini: "gemini"
        case .antigravity: "agy"
        case .shell: nil
        }
    }
}

@MainActor
final class BrowserAgentTerminalManager: ObservableObject, LocalProcessTerminalViewDelegate {
    @Published var isPanelVisible = false
    @Published var selectedCLI: BrowserAgentCLI = .claude
    @Published private(set) var terminalView: LocalProcessTerminalView?
    @Published private(set) var isStarting = false
    @Published private(set) var isProcessRunning = false
    @Published private(set) var terminalTitle = "NF Browser Agent"
    @Published private(set) var statusMessage: String?
    @Published private(set) var setupError: String?

    let browserBridge = BrowserAgentBridge()
    let contentFraction = FractionHolder.usingUserDefaults(0.68, key: "browser.agent.contentFraction")
    let hiddenPanel = SideHolder(.secondary)

    private weak var tabManager: TabManager?
    private var workspace: BrowserAgentWorkspace?

    func attach(tabManager: TabManager) {
        self.tabManager = tabManager
        browserBridge.attach(tabManager: tabManager)
    }

    func togglePanel() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            isPanelVisible.toggle()
            hiddenPanel.side = isPanelVisible ? nil : .secondary
        }
        if isPanelVisible {
            do {
                workspace = try BrowserAgentWorkspace.prepare()
                setupError = nil
            } catch {
                setupError = error.localizedDescription
            }
        }
    }

    func startSelectedCLI() {
        guard !isStarting, !isProcessRunning else { return }
        isStarting = true
        Task {
            defer { isStarting = false }
            do {
                try await startSession()
            } catch {
                setupError = error.localizedDescription
            }
        }
    }

    func stopCurrentSession() {
        let runningTerminal = terminalView
        terminalView = nil
        isStarting = false
        isProcessRunning = false
        statusMessage = "Terminal session stopped"
        browserBridge.stop()
        runningTerminal?.terminate()
    }

    private func startSession() async throws {
        if isProcessRunning {
            throw TerminalError.alreadyRunning
        }
        if workspace == nil {
            workspace = try BrowserAgentWorkspace.prepare()
        }
        guard let workspace else { throw TerminalError.workspaceUnavailable }

        try await browserBridge.start()
        guard let endpoint = browserBridge.endpoint else { throw TerminalError.bridgeUnavailable }

        var environment = browserBridge.environmentValues()
        let inheritedPath = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let localBin = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        environment["PATH"] = "\(workspace.tools.path):\(localBin):\(inheritedPath)"
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["SHELL"] = "/bin/zsh"
        environment["ORA_BROWSER_ENDPOINT"] = endpoint

        let view = LocalProcessTerminalView(
            frame: .zero,
            font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            options: .default
        )
        view.processDelegate = self
        terminalView = view
        isProcessRunning = true
        terminalTitle = "NF Browser Agent"
        setupError = nil
        statusMessage = "Connecting browser skill…"

        let args: [String]
        if let command = selectedCLI.command {
            args = ["-l", "-i", "-c", "exec \(command)"]
            statusMessage = "Starting \(selectedCLI.title)…"
        } else {
            args = ["-l", "-i"]
            statusMessage = "Shell ready — run claude, codex, gemini, or agy"
        }
        view.startProcess(
            executable: "/bin/zsh",
            args: args,
            environment: environment.map { "\($0.key)=\($0.value)" },
            currentDirectory: workspace.root.path
        )
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.terminalTitle = title.isEmpty ? "NF Browser Agent" : title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        let sourceIdentifier = ObjectIdentifier(source)
        Task { @MainActor [weak self] in
            self?.handleProcessTermination(sourceIdentifier: sourceIdentifier, exitCode: exitCode)
        }
    }

    private func handleProcessTermination(sourceIdentifier: ObjectIdentifier, exitCode: Int32?) {
        guard let terminalView, ObjectIdentifier(terminalView) == sourceIdentifier else { return }
        isProcessRunning = false
        statusMessage = exitCode.map { "Process exited with code \($0)" } ?? "Process ended"
        browserBridge.stop()
    }
}

private enum TerminalError: LocalizedError {
    case alreadyRunning
    case workspaceUnavailable
    case bridgeUnavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A terminal session is already running"
        case .workspaceUnavailable: "Could not prepare the browser agent workspace"
        case .bridgeUnavailable: "Could not connect the browser control session"
        }
    }
}

private struct BrowserAgentWorkspace {
    let root: URL
    let tools: URL

    static func prepare() throws -> Self {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NFBrowser", isDirectory: true)
            .appendingPathComponent("Browser Agent", isDirectory: true)
        let legacyAppSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ora", isDirectory: true)
            .appendingPathComponent("Browser Agent", isDirectory: true)

        // Migrate any existing workspace files from legacy "Ora/Browser Agent"
        if !FileManager.default.fileExists(atPath: appSupport.path),
           FileManager.default.fileExists(atPath: legacyAppSupport.path)
        {
            try? FileManager.default.copyItem(at: legacyAppSupport, to: appSupport)
        }

        let tools = appSupport.appendingPathComponent("Tools", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)

        let skill = try bundledResource(named: "SKILL.md")
        let command = try bundledResource(named: "ora-browser.py")
        for relativePath in [
            ".agents/skills/nf-browser/SKILL.md",
            ".agents/skills/ora-browser/SKILL.md",
            ".claude/skills/nf-browser/SKILL.md",
            ".claude/skills/ora-browser/SKILL.md",
            ".gemini/skills/nf-browser/SKILL.md",
            ".gemini/skills/ora-browser/SKILL.md"
        ] {
            let destination = appSupport.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try skill.write(to: destination, atomically: true, encoding: .utf8)
        }

        let nfCommandPath = tools.appendingPathComponent("nf-browser")
        try command.write(to: nfCommandPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nfCommandPath.path)

        let commandPath = tools.appendingPathComponent("ora-browser")
        try command.write(to: commandPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: commandPath.path)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return Self(root: appSupport, tools: tools)
    }

    private static func bundledResource(named name: String) throws -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: nil) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        guard let resourceRoot = Bundle.main.resourceURL,
              let enumerator = FileManager.default.enumerator(at: resourceRoot, includingPropertiesForKeys: nil)
        else { throw WorkspaceError.resourceMissing(name) }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw WorkspaceError.resourceMissing(name)
    }
}

private enum WorkspaceError: LocalizedError {
    case resourceMissing(String)

    var errorDescription: String? {
        switch self {
        case let .resourceMissing(name): "NF Browser could not find its bundled browser-agent resource: \(name)"
        }
    }
}
