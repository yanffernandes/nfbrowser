import SwiftUI

struct ContainerView: View {
    let container: TabContainer
    let selectedContainer: String
    let containers: [TabContainer]

    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolbarManager: ToolbarManager
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var privacyMode: PrivacyMode
    @EnvironmentObject var toastManager: ToastManager
    @State private var draggedItem: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if toolbarManager.isToolbarHidden {
                SidebarURLDisplay()
            }
            if !privacyMode.isPrivate {
                // Space Header: Name and Engine Badge
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: container.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.foreground)

                    Text(container.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)

                    Spacer()

                    // Engine Badge
                    HStack(spacing: 4) {
                        Image(systemName: container.engineKind.iconSystemName)
                            .font(.system(size: 9, weight: .medium))
                        Text(container.engineKind.displayName)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        container.engineKind == .chromium
                            ? Color.blue.opacity(0.18)
                            : theme.mutedBackground
                    )
                    .foregroundColor(
                        container.engineKind == .chromium
                            ? Color.blue
                            : theme.mutedForeground
                    )
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    SidebarTabSectionHeader(
                        title: "Favorites",
                        count: favoriteTabs.count,
                        systemImage: "star.fill"
                    )
                    FavTabsGrid(
                        tabs: favoriteTabs,
                        draggedItem: $draggedItem,
                        onDrag: dragTab,
                        selectedContainerId: selectedContainer,
                        onSelect: selectTab,
                        onFavoriteToggle: toggleFavorite,
                        onClose: removeTab,
                        onDuplicate: duplicateTab,
                        onMoveToContainer: moveTab
                    )
                }
            } else {
                VStack(alignment: .center, spacing: 8) {
                    Text("Private Browsing")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("Your activity is not being saved")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
                .padding(.horizontal)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if !privacyMode.isPrivate {
                        PinnedTabsList(
                            tabs: pinnedTabs,
                            draggedItem: $draggedItem,
                            onDrag: dragTab,
                            onSelect: selectTab,
                            onPinToggle: togglePin,
                            onFavoriteToggle: toggleFavorite,
                            onClose: removeTab,
                            onDuplicate: duplicateTab,
                            onMoveToContainer: moveTab,
                            containers: containers
                        )
                        Divider()
                    }
                    SidebarTabSectionHeader(
                        title: "Open tabs",
                        count: normalTabs.count,
                        systemImage: "rectangle.stack"
                    )
                    NormalTabsList(
                        tabs: normalTabs,
                        draggedItem: $draggedItem,
                        onDrag: dragTab,
                        onSelect: selectTab,
                        onPinToggle: togglePin,
                        onFavoriteToggle: toggleFavorite,
                        onClose: removeTab,
                        onDuplicate: duplicateTab,
                        onMoveToContainer: moveTab,
                        onAddNewTab: addNewTab
                    )
                }
            }
        }
    }

    private var favoriteTabs: [Tab] {
        return container.tabs
            .filter { $0.type == .fav }
            .sorted(by: { $0.order > $1.order })
    }

    private var pinnedTabs: [Tab] {
        return container.tabs
            .sorted(by: { $0.order > $1.order })
            .filter { $0.type == .pinned }
    }

    private var normalTabs: [Tab] {
        return container.tabs
            .sorted(by: { $0.order > $1.order })
            .filter { $0.type == .normal }
    }

    private func addNewTab() {
        appState.showLauncher = true
    }

    private func removeTab(_ tab: Tab) {
        tabManager.closeTab(tab: tab)
    }

    private func togglePin(_ tab: Tab) {
        tabManager.togglePinTab(tab)
    }

    private func toggleFavorite(_ tab: Tab) {
        tabManager.toggleFavTab(tab)
    }

    private func selectTab(_ tab: Tab) {
        tabManager.activateTab(tab)
    }

    private func moveTab(
        _ tab: Tab,
        _ newContainer: TabContainer
    ) {
        tabManager
            .moveTabToContainer(
                tab,
                toContainer: newContainer
            )
        toastManager.show(
            "Moved to \(newContainer.name)",
            icon: .system("arrow.right.arrow.left")
        )
    }

    private func dragTab(_ tabId: UUID) -> NSItemProvider {
        draggedItem = tabId
        let provider = TabItemProvider(object: tabId.uuidString as NSString)
        provider.didEnd = {
            draggedItem = nil
        }
        return provider
    }

    private func dropTab(_ tabId: String) {
        draggedItem = nil
    }

    private func duplicateTab(_ tab: Tab) {
        tabManager.duplicateTab(tab)
    }
}

struct SidebarTabSectionHeader: View {
    let title: String
    let count: Int
    let systemImage: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            Text(count.formatted())
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.mutedBackground, in: Capsule())
        }
        .foregroundStyle(theme.mutedForeground)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

class TabItemProvider: NSItemProvider {
    var didEnd: (() -> Void)?
    deinit {
        didEnd?()
    }
}
