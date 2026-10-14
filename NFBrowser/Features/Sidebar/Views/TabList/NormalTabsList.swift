import SwiftData
import SwiftUI

struct NormalTabsList: View {
    let tabs: [Tab]
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void
    let onMoveToContainer:
        (
            Tab,
            TabContainer
        ) -> Void
    let onAddNewTab: () -> Void
    @Query var containers: [TabContainer]
    @EnvironmentObject var tabManager: TabManager
    @State private var previousTabIds: [UUID] = []

    private var rootTabs: [Tab] {
        tabs.filter { $0.folder == nil }
    }

    private var folders: [Folder] {
        tabManager.activeContainer?.folders ?? []
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                NewTabButton(addNewTab: onAddNewTab)

                Button(action: {
                    if let container = tabManager.activeContainer {
                        let count = container.folders.count + 1
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            tabManager.createFolder(name: "Folder \(count)", in: container)
                        }
                    }
                }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("New Folder")
            }

            // Folders
            ForEach(folders) { folder in
                FolderItemView(
                    folder: folder,
                    draggedItem: $draggedItem,
                    onDrag: onDrag,
                    onSelect: onSelect,
                    onPinToggle: onPinToggle,
                    onFavoriteToggle: onFavoriteToggle,
                    onClose: onClose,
                    onDuplicate: onDuplicate,
                    onMoveToContainer: onMoveToContainer,
                    onAddNewTabInFolder: { targetFolder in
                        if let container = tabManager.activeContainer {
                            let newTab = tabManager.openTab(
                                url: URL(string: "about:blank")!,
                                historyManager: tabManager.historyManager ?? HistoryManager(modelContainer: tabManager.modelContainer, modelContext: tabManager.modelContext),
                                downloadManager: tabManager.downloadManager,
                                isPrivate: false
                            )
                            if let newTab {
                                tabManager.moveTab(newTab, to: targetFolder)
                            }
                        }
                    },
                    containers: containers
                )
            }

            // Loose tabs (not in any folder)
            ForEach(rootTabs) { tab in
                TabItem(
                    tab: tab,
                    isSelected: tabManager.isActive(tab),
                    isDragging: draggedItem == tab.id,
                    onTap: { onSelect(tab) },
                    onPinToggle: { onPinToggle(tab) },
                    onFavoriteToggle: { onFavoriteToggle(tab) },
                    onClose: { onClose(tab) },
                    onDuplicate: { onDuplicate(tab) },
                    onMoveToContainer: { onMoveToContainer(tab, $0) },
                    availableContainers: containers
                )
                .onDrag { onDrag(tab.id) }
                .onDrop(
                    of: [.text],
                    delegate: TabDropDelegate(
                        item: tab,
                        draggedItem: $draggedItem,
                        targetSection: .normal
                    )
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
                .animation(.spring(response: 0.22, dampingFraction: 0.85), value: rootTabs.map(\.id))
            }
        }
        .onDrop(
            of: [.text],
            delegate: SectionDropDelegate(
                items: tabs,
                draggedItem: $draggedItem,
                targetSection: .normal,
                tabManager: tabManager
            )
        )
        .onAppear {
            previousTabIds = tabs.map(\.id)
        }
        .onChange(of: tabs.map(\.id)) { _, newTabIds in
            previousTabIds = newTabIds
        }
    }

    private func shouldAnimate(_ tab: Tab) -> Bool {
        // Only animate if the tab's position has actually changed
        guard let currentIndex = tabs.firstIndex(where: { $0.id == tab.id }),
              let previousIndex = previousTabIds.firstIndex(where: { $0 == tab.id })
        else {
            return true // Animate new tabs or tabs that were just created
        }
        return currentIndex != previousIndex
    }
}
