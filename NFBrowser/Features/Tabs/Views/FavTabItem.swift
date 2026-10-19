import AppKit
import SwiftData
import SwiftUI

struct FavTabItem: View {
    let tab: Tab
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onMoveToContainer: (TabContainer) -> Void

    @Environment(\.theme) private var theme
    @Query var containers: [TabContainer]
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode
    @State private var isHovering = false
    @State private var lastClickTime: Date? = nil

    private func handleTap() {
        let now = Date()
        if let last = lastClickTime, now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
            lastClickTime = nil
            tab.promptRename()
        } else {
            lastClickTime = now
            onTap()
            if !tab.isWebViewReady {
                tab.restoreTransientState(
                    historyManager: historyManager,
                    downloadManager: downloadManager,
                    tabManager: tabManager,
                    isPrivate: privacyMode.isPrivate
                )
            }
        }
    }

    var body: some View {
        ZStack {
            FavIcon(
                isWebViewReady: tab.isWebViewReady,
                favicon: tab.favicon,
                faviconLocalFile: tab.faviconLocalFile,
                textColor: Color(.white),
                domain: tab.url.host,
                isPlayingMedia: false,
                fallbackSystemImage: tab.url.isFileURL ? "doc.text" : "globe",
                size: 20
            )

            if tab.isPlayingMedia {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image(systemName: "speaker.wave.2.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 8, height: 8)
                            .foregroundColor(.white.opacity(0.9))
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 12, height: 12)
                            )
                    }
                }
                .padding(2)
            }
        }
        .onAppear {
            if tabManager.isActive(tab) {
                tab
                    .restoreTransientState(
                        historyManager: historyManager,
                        downloadManager: downloadManager,
                        tabManager: tabManager,
                        isPrivate: privacyMode.isPrivate
                    )
            }
        }
        .foregroundColor(theme.foreground)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .opacity(isDragging ? 0.0 : 1.0)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            isDragging
                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                : isSelected
                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    Color.accentColor,
                    lineWidth: 1.5
                )
                : nil
        )
        .animation(.easeInOut(duration: 0.14), value: isHovering)
        .animation(.easeInOut(duration: 0.1), value: isSelected)
        .onTapGesture {
            handleTap()
        }
        .onHover { isHovering = $0 }
        .help(tab.displayTitle)
        .contextMenu {
            Button(action: {
                tab.promptRename()
            }) {
                Label("Rename Tab", systemImage: "pencil")
            }

            if tab.customTitle != nil {
                Button(action: {
                    tab.resetTitle()
                }) {
                    Label("Reset to Original Title", systemImage: "arrow.counterclockwise")
                }
            }

            Divider()

            Button(action: onFavoriteToggle) {
                Label("Remove from Favorites", systemImage: "star.slash")
            }

            Button(action: onDuplicate) {
                Label("Duplicate Tab", systemImage: "doc.on.doc")
            }

            // Divider()

            //      Menu("Move to Container") {
            //        ForEach(containers) { container in
            //            if container.id != tabManager.activeContainer?.id {
            //            Button(action: { onMoveToContainer(container) }) {
            //              Label(container.title, systemImage: container.icon)
            //            }
            //          }
            //        }
            //      }

            Divider()

            Button(role: .destructive, action: onClose) {
                Label("Close Tab", systemImage: "xmark")
            }
        }
    }

    private var backgroundColor: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isSelected {
            return theme.invertedSolidWindowBackgroundColor.opacity(0.3)
        } else if isHovering {
            return theme.activeTabBackground.opacity(0.3)
        }
        return theme.mutedBackground
    }
}
