import AppKit
import SwiftTerm
import SwiftUI

struct BrowserAgentTerminalPanel: View {
    @EnvironmentObject private var manager: BrowserAgentTerminalManager
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.mutedForeground)

                Picker("Agent", selection: $manager.selectedCLI) {
                    ForEach(BrowserAgentCLI.allCases) { cli in
                        Text(cli.title).tag(cli)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: 160)
                .disabled(manager.isProcessRunning || manager.isStarting)

                if manager.isProcessRunning, manager.terminalTitle != "NF Browser Agent" {
                    Text(manager.terminalTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 170, alignment: .leading)
                }

                Spacer(minLength: 8)

                Button {
                    manager.startSelectedCLI()
                } label: {
                    Label(
                        manager.isStarting ? "Starting" : manager.isProcessRunning ? "Running" : "Start",
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(manager.isProcessRunning || manager.isStarting)
                .help("Start the selected local agent CLI")

                if manager.isProcessRunning {
                    Button {
                        manager.stopCurrentSession()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Stop the terminal session")
                }

                Button {
                    manager.togglePanel()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Hide the agent terminal")
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(theme.subtleWindowBackgroundColor)

            if manager.selectedCLI == .gemini || manager.selectedCLI == .antigravity {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(googleAccountNote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.subtleWindowBackgroundColor.opacity(0.75))
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.open")
                Text("The selected CLI runs with your macOS user permissions and uses its own local sign-in.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10))
            .foregroundStyle(theme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.subtleWindowBackgroundColor.opacity(0.55))

            if let error = manager.setupError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }

            Group {
                if let terminal = manager.terminalView {
                    BrowserAgentTerminalHost(terminal: terminal)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))

            HStack(spacing: 6) {
                Circle()
                    .fill(manager.browserBridge.isRunning ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(manager.statusMessage ?? "Sign-in and billing stay with the selected CLI")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(manager.setupError == nil ? "Browser skill ready" : "Skill unavailable")
                    .foregroundStyle(manager.setupError == nil ? theme.mutedForeground : .red)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background(theme.subtleWindowBackgroundColor)
        }
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(width: 1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.mutedForeground)
            Text("Run your agent beside the page")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.foreground)
            Text(
                "NF Browser opens the CLI you already use. Its sign-in and account stay with that CLI. The ora-browser skill lets it read and control this browser's active tab."
            )
            .font(.system(size: 12))
            .foregroundStyle(theme.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
            Text("Choose an agent above, then press Start. Choose Shell to run a command manually.")
                .font(.system(size: 11))
                .foregroundStyle(theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 340, alignment: .leading)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var googleAccountNote: String {
        if manager.selectedCLI == .gemini {
            return "Google ended Gemini CLI access through consumer AI subscriptions. Use a supported API key or Enterprise account."
        }
        return "Google's terms restrict third-party apps from accessing Antigravity with personal accounts. Use an Enterprise account."
    }
}

private struct BrowserAgentTerminalHost: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}
