import SwiftUI

struct BrowserTabSplitContainer: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    let activeTab: Tab

    @State private var splitFraction = FractionHolder(0.50)

    var body: some View {
        Group {
            if let splitTab = tabManager.splitTab {
                HSplit(
                    left: {
                        BrowserWebContentView(tab: activeTab)
                    },
                    right: {
                        secondarySplitPane(tab: splitTab)
                    }
                )
                .fraction(splitFraction)
                .splitter {
                    TabSplitDivider()
                }
                .constraints(minPFraction: 0.25, minSFraction: 0.25, priority: .primary)
                .styling(visibleThickness: 1)
            } else {
                BrowserWebContentView(tab: activeTab)
            }
        }
    }

    private func secondarySplitPane(tab: Tab) -> some View {
        VStack(spacing: 0) {
            // Refined header for secondary split view
            HStack(spacing: 8) {
                FavIcon(
                    isWebViewReady: tab.isWebViewReady,
                    favicon: tab.favicon,
                    faviconLocalFile: tab.faviconLocalFile,
                    textColor: .white,
                    isPlayingMedia: tab.isPlayingMedia
                )

                Text(tab.displayTitle.isEmpty ? tab.urlString : tab.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                // Engine Pill
                Text(tab.container.engineKind.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.18))
                    .foregroundColor(Color.accentColor)
                    .clipShape(Capsule())

                // Swap Split View Sides
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        tabManager.swapSplitTabs()
                    }
                }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("Swap Left and Right Tabs")

                // Close Split View
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tabManager.closeSplitTab()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close Split View (Esc)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.35))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            BrowserWebContentView(tab: tab)
        }
        .background(theme.background)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1)
        }
    }
}

@MainActor
private struct TabSplitDivider: SplitDivider {
    public var styling: SplitStyling
    @State private var isHovering = false
    @State private var isCursorPushed = false

    init() {
        self.styling = SplitStyling(color: .clear, inset: 0, visibleThickness: 1, invisibleThickness: 14)
    }

    init(styling: SplitStyling) {
        self.styling = styling
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 14)

            Rectangle()
                .fill(isHovering ? Color.white.opacity(0.50) : Color.white.opacity(0.15))
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isCursorPushed {
                NSCursor.resizeLeftRight.push()
                isCursorPushed = true
            } else if !hovering && isCursorPushed {
                NSCursor.pop()
                isCursorPushed = false
            }
        }
        .onDisappear {
            if isCursorPushed {
                NSCursor.pop()
                isCursorPushed = false
            }
        }
    }
}
