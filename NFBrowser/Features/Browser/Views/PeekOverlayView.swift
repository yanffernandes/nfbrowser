import AppKit
import SwiftUI

struct PeekOverlayView: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject private var tabManager: TabManager
    @Environment(\.theme) private var theme

    @State private var isHoveringClose = false
    @State private var isHoveringPromote = false
    @State private var isHoveringCopy = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Dimmed semi-transparent backdrop
                Color.black.opacity(0.50)
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        tabManager.closePeek()
                    }

                // Main floating Peek card
                VStack(spacing: 0) {
                    headerBar
                    webContentView
                }
                .frame(
                    width: max(500, min(proxy.size.width - 120, 1280)),
                    height: max(400, min(proxy.size.height - 80, 900))
                )
                .background(theme.background)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 36, x: 0, y: 14)
                // Floating top-right action buttons (Arc / Orca style)
                .overlay(alignment: .topTrailing) {
                    floatingActionControls
                        .offset(x: 52, y: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            // Navigation controls
            HStack(spacing: 6) {
                Button {
                    tab.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoBack)
                .opacity(tab.canGoBack ? 1.0 : 0.35)
                .help("Go Back")

                Button {
                    tab.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!tab.canGoForward)
                .opacity(tab.canGoForward ? 1.0 : 0.35)
                .help("Go Forward")

                Button {
                    tab.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Reload")
            }
            .foregroundStyle(theme.mutedForeground)

            Spacer()

            // URL host pill
            HStack(spacing: 6) {
                Image(systemName: tab.url.scheme == "https" ? "lock.fill" : "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(tab.url.scheme == "https" ? Color.green.opacity(0.85) : theme.mutedForeground)

                Text(cleanHost)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))

            Spacer()

            // Promote to Tab action button
            Button {
                tabManager.promotePeekTab()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 11, weight: .medium))
                    Text("Manter como aba")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.20), in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.50), lineWidth: 0.5))
                .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help("Promote to a permanent tab in sidebar")

            // Copy Link
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.mutedForeground)
            }
            .buttonStyle(.plain)
            .help("Copy link")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(theme.subtleWindowBackgroundColor)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Floating Controls (Side of Peek Window)

    private var floatingActionControls: some View {
        VStack(spacing: 8) {
            // Close Button (X)
            Button {
                tabManager.closePeek()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.70), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close Peek (Esc)")

            // Expand to Tab
            Button {
                tabManager.promotePeekTab()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.70), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Open as full tab")

            // Dock to Sidebar
            Button {
                tabManager.promotePeekTab()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.70), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Keep as sidebar tab")
        }
    }

    // MARK: - Web Content View

    @ViewBuilder
    private var webContentView: some View {
        ZStack(alignment: .top) {
            if tab.isWebViewReady, let page = tab.browserPage {
                BrowserPageView(page: page)
                    .id(tab.id)
                    .overlay(alignment: .bottomLeading) {
                        if let hovered = tab.hoveredLinkURL, !hovered.isEmpty {
                            LinkPreview(text: hovered)
                        }
                    }
            } else {
                ZStack {
                    Rectangle().fill(theme.background)
                    ProgressView()
                        .frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Progress bar
            if tab.isLoading {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * CGFloat(max(0.05, min(1.0, tab.loadingProgress / 100.0))), height: 2.5)
                        .animation(.linear(duration: 0.1), value: tab.loadingProgress)
                }
                .frame(height: 2.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cleanHost: String {
        tab.url.host?.replacingOccurrences(of: "www.", with: "") ?? tab.title
    }
}
