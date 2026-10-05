import AppKit
import SwiftUI

struct LocalFavIcon: View {
    let faviconLocalFile: URL?
    let textColor: Color

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .cornerRadius(4)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundColor(textColor)
            }
        }
        .task(id: faviconLocalFile) { loadFavicon() }
    }

    private func loadFavicon() {
        guard let localURL = faviconLocalFile,
              FileManager.default.fileExists(atPath: localURL.path) else { return }

        // Loading may block briefly, so you can even do it async if needed
        DispatchQueue.global(qos: .utility).async {
            if let loadedImage = NSImage(contentsOfFile: localURL.path) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}

struct FavIcon: View {
    let isWebViewReady: Bool
    let favicon: URL?
    let faviconLocalFile: URL?
    let textColor: Color
    var isPlayingMedia: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let favicon, isWebViewReady {
                AsyncImage(
                    url: favicon
                ) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } placeholder: {
                    LocalFavIcon(
                        faviconLocalFile: faviconLocalFile,
                        textColor: textColor
                    )
                }
            } else {
                LocalFavIcon(
                    faviconLocalFile: faviconLocalFile,
                    textColor: textColor
                )
            }

            if isPlayingMedia {
                Image(systemName: "speaker.wave.2.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .foregroundColor(textColor.opacity(0.8))
            }
        }
        .frame(width: isPlayingMedia ? 28 : 16, height: 16)
    }
}

struct TabItem: View {
    let tab: Tab
    let isSelected: Bool
    let isDragging: Bool
    let onTap: () -> Void
    let onPinToggle: () -> Void
    let onFavoriteToggle: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onMoveToContainer: (TabContainer) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var historyManager: HistoryManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var privacyMode: PrivacyMode
    let availableContainers: [TabContainer]

    @Environment(\.theme) private var theme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    FavIcon(
                        isWebViewReady: tab.isWebViewReady,
                        favicon: tab.favicon,
                        faviconLocalFile: tab.faviconLocalFile,
                        textColor: textColor,
                        isPlayingMedia: tab.isPlayingMedia
                    )
                    tabTitle
                    if tab.isAgentActive {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TabItemButtonStyle())
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    tab.promptRename()
                }
            )

            actionButton
                .opacity(isHovering ? 1.0 : 0.0)
                .scaleEffect(isHovering ? 1.0 : 0.85)
                .allowsHitTesting(isHovering)
                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovering)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
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
        .opacity(isDragging ? 0.0 : 1.0)
        .background(backgroundColor, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.85) : .clear, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 20)
                    .padding(.leading, 3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .overlay(
            isDragging ?
                ConditionallyConcentricRectangle(cornerRadius: 10)
                .stroke(
                    theme.invertedSolidWindowBackgroundColor.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
                : nil
        )
        .background(
            PreciseHoverArea(isHovered: $isHovering)
        )
        .contextMenu { contextMenuItems }
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isDragging)
        .animation(.easeInOut(duration: 0.14), value: isHovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: isSelected)
        .geometryGroup()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tabTitle: some View {
        Text(tab.displayTitle)
            .font(.system(size: 13))
            .foregroundColor(textColor)
            .lineLimit(1)
    }

    private var backgroundColor: Color {
        if isDragging {
            return theme.activeTabBackground.opacity(0.1)
        } else if isSelected {
            return theme.activeTabBackground
        } else if isHovering {
            if colorScheme == .dark {
                return theme.activeTabBackground.opacity(0.3)
            } else {
                return theme.activeTabBackground.opacity(0.1)
            }
        }
        return .clear
    }

    private var textColor: Color {
        isSelected ? .white : theme.foreground
    }

    @ViewBuilder
    private var actionButton: some View {
        if tab.type == .pinned, !tab.isWebViewReady {
            ActionButton(icon: "pin.slash", color: textColor, action: onPinToggle).help("Unpin Tab")
        } else {
            ActionButton(icon: "xmark", color: textColor, action: onClose).help("Close Tab")
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
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

        Button(action: onPinToggle) {
            Label(
                tab.type == .pinned ? "Unpin Tab" : "Pin Tab",
                systemImage: tab.type == .pinned ? "pin.slash" : "pin"
            )
        }

        Button(action: onFavoriteToggle) {
            Label(
                tab.type == .fav ? "Remove from Favorites" : "Add to Favorites",
                systemImage: tab.type == .fav ? "star.slash" : "star"
            )
        }

        Button(action: onDuplicate) {
            Label("Duplicate Tab", systemImage: "doc.on.doc")
        }
        .disabled(!tab.isWebViewReady)

        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if tabManager.splitTab?.id == tab.id {
                    tabManager.closeSplitTab()
                } else {
                    tabManager.openSplitTab(tab)
                }
            }
        }) {
            Label(
                tabManager.splitTab?.id == tab.id ? "Close from Split View" : "Open in Split View",
                systemImage: "rectangle.split.2x1"
            )
        }

        Divider()

        if availableContainers.count > 1 {
            Divider()

            Menu("Move to Container") {
                ForEach(availableContainers) { container in
                    if tab.container.id != container.id {
                        Button(action: { onMoveToContainer(container) }) {
                            Label(container.name, systemImage: container.systemImage)
                        }
                    }
                }
            }

            Divider()
        }

        Button(role: .destructive, action: onClose) {
            Label("Close Tab", systemImage: "xmark")
        }
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(isHovering ? .white : color.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(isHovering ? Color.white.opacity(0.24) : Color.clear)
                )
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.12), value: isHovering)
                .contentShape(Circle())
        }
        .buttonStyle(TactileBarButtonStyle())
        .onHover { isHovering = $0 }
    }
}
