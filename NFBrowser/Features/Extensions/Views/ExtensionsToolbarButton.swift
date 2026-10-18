import AppKit
import SwiftUI
import WebKit

struct ExtensionsToolbarButton: View {
    @ObservedObject var extensionManager = ExtensionManager.shared
    let foregroundColor: Color

    @State private var isShowingPopover: Bool = false
    @State private var activePopupAction: WKWebExtension.Action? = nil
    @State private var isShowingActionPopup: Bool = false

    var body: some View {
        Button(action: { isShowingPopover.toggle() }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isShowingPopover ? Color.accentColor : foregroundColor)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())

                if extensionManager.installedExtensions.contains(where: \.isEnabled) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                        .offset(x: -4, y: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            ExtensionsMenuPopover(
                onOpenActionPopup: { action in
                    isShowingPopover = false
                    activePopupAction = action
                    isShowingActionPopup = true
                }
            )
        }
        .popover(isPresented: $isShowingActionPopup, arrowEdge: .bottom) {
            if let activePopupAction, let popupWebView = activePopupAction.popupWebView {
                ExtensionPopupHostView(webView: popupWebView)
                    .frame(width: 380, height: 480)
            }
        }
        .help("Extensões (Chrome Web Store)")
    }
}

struct ExtensionPopupHostView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ExtensionsMenuPopover: View {
    @ObservedObject var extensionManager = ExtensionManager.shared
    let onOpenActionPopup: (WKWebExtension.Action) -> Void

    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.accentColor)
                    Text("Extensões")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                if extensionManager.isInstalling {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if let message = extensionManager.installStatusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                Divider()
            }

            // List of extensions
            if extensionManager.installedExtensions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Nenhuma extensão instalada")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Acesse a Chrome Web Store para adicionar extensões com 1 clique.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(extensionManager.installedExtensions) { item in
                            ExtensionRowView(
                                item: item,
                                onActionClick: {
                                    if let action = extensionManager.action(for: item), action.popupWebView != nil {
                                        onOpenActionPopup(action)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 280)
            }

            Divider()

            // Footer actions
            VStack(spacing: 4) {
                Button(action: openChromeWebStore) {
                    HStack {
                        Image(systemName: "bag.badge.plus")
                            .frame(width: 16)
                        Text("Abrir Chrome Web Store")
                            .font(.system(size: 12))
                        Spacer()
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(ExtensionItemButtonStyle())

                Button(action: loadUnpackedFolder) {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                            .frame(width: 16)
                        Text("Carregar Extensão da Pasta...")
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(ExtensionItemButtonStyle())
            }
            .padding(6)
        }
        .frame(width: 300)
    }

    private func openChromeWebStore() {
        if let url = URL(string: "https://chromewebstore.google.com") {
            NotificationCenter.default.post(name: .openURL, object: nil, userInfo: ["url": url])
        }
    }

    private func loadUnpackedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Selecionar Pasta"

        if panel.runModal() == .OK, let selectedURL = panel.url {
            Task {
                do {
                    try await extensionManager.installFromLocalDirectory(url: selectedURL)
                    ToastManager.shared.show("Extensão carregada com sucesso!", type: .success, icon: .system("puzzlepiece.extension"))
                } catch {
                    ToastManager.shared.show("Erro: \(error.localizedDescription)", type: .error, icon: .system("exclamationmark.triangle"))
                }
            }
        }
    }
}

struct ExtensionRowView: View {
    let item: ExtensionItem
    let onActionClick: () -> Void
    @ObservedObject var extensionManager = ExtensionManager.shared

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            if let iconURL = item.iconURL, let img = NSImage(contentsOf: iconURL) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .cornerRadius(4)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("v\(item.version)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // If action exists, show action button
            if let action = extensionManager.action(for: item), action.popupWebView != nil, item.isEnabled {
                Button(action: onActionClick) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Abrir popup da extensão")
            }

            // Enable toggle
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { _ in extensionManager.toggleExtension(item) }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.65)
            .frame(width: 32)

            // Remove button
            Button(action: { extensionManager.uninstallExtension(item) }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Remover extensão")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { isHovering = $0 }
    }
}

struct ExtensionItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.secondary.opacity(0.12) : Color.clear)
            )
            .onHover { isHovered = $0 }
    }
}
