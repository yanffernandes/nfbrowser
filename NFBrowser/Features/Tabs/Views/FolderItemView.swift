import SwiftData
import SwiftUI

struct FolderItemView: View {
    let folder: Folder
    @Binding var draggedItem: UUID?
    let onDrag: (UUID) -> NSItemProvider
    let onSelect: (Tab) -> Void
    let onPinToggle: (Tab) -> Void
    let onFavoriteToggle: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onDuplicate: (Tab) -> Void
    let onMoveToContainer: (Tab, TabContainer) -> Void
    let onAddNewTabInFolder: (Folder) -> Void
    let containers: [TabContainer]

    @EnvironmentObject private var tabManager: TabManager
    @Environment(\.theme) private var theme
    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var newFolderName = ""

    private var sortedTabs: [Tab] {
        folder.tabs
            .filter { $0.type == .normal }
            .sorted(by: { $0.order > $1.order })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Folder header row
            HStack(spacing: 6) {
                // Expand / Collapse Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(folder.isOpened ? 90 : 0))
                    .frame(width: 14, height: 14)

                // Folder Icon
                Image(systemName: folder.isOpened ? "folder.fill" : "folder")
                    .font(.system(size: 12))
                    .foregroundColor(theme.accent)

                if isRenaming {
                    TextField("Folder name", text: $newFolderName, onCommit: {
                        tabManager.renameFolder(folder, to: newFolderName)
                        isRenaming = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                } else {
                    Text(folder.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)
                }

                Spacer()

                // Count badge
                if !sortedTabs.isEmpty {
                    Text("\(sortedTabs.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                }

                // Quick add tab button on hover
                if isHovering {
                    Button(action: { onAddNewTabInFolder(folder) }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("New Tab in “\(folder.name)”")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? theme.foreground.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .onTapGesture {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                    tabManager.toggleFolder(folder)
                }
            }
            .contextMenu {
                Button(action: { onAddNewTabInFolder(folder) }) {
                    Label("New Tab in Folder", systemImage: "plus")
                }

                Button(action: {
                    newFolderName = folder.name
                    isRenaming = true
                }) {
                    Label("Rename Folder...", systemImage: "pencil")
                }

                Divider()

                Button(action: {
                    tabManager.deleteFolder(folder, closeContainedTabs: false)
                }) {
                    Label("Delete Folder (Keep Tabs)", systemImage: "folder.badge.minus")
                }

                Button(role: .destructive, action: {
                    tabManager.deleteFolder(folder, closeContainedTabs: true)
                }) {
                    Label("Close All Tabs and Delete", systemImage: "trash")
                }
            }

            // Tabs inside folder when open
            if folder.isOpened {
                VStack(spacing: 4) {
                    ForEach(sortedTabs) { tab in
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
                        .padding(.leading, 14)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}
