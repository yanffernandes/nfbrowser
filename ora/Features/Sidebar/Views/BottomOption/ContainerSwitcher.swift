import SwiftData
import SwiftUI

struct ContainerSwitcher: View {
    let onContainerSelected: (TabContainer) -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var dialogManager: DialogManager
    @Query var containers: [TabContainer]

    @State private var hoveredContainer: UUID?

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let totalWidth =
                CGFloat(containers.count) * ContainerConstants.UI.normalButtonWidth + CGFloat(max(
                    0,
                    containers.count - 1
                ))
                * 2
            let isCompact = totalWidth > availableWidth

            HStack(alignment: .center, spacing: isCompact ? 4 : 2) {
                ForEach(orderedContainers, id: \.id) { container in
                    containerButton(for: container, isCompact: isCompact)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(0)
        }
        .padding(0)
        .frame(height: 28)
    }

    private var orderedContainers: [TabContainer] {
        containers.sorted(by: TabContainer.stableSort)
    }

    @ViewBuilder
    private func containerButton(for container: TabContainer, isCompact: Bool)
        -> some View
    {
        let isActive = tabManager.activeContainer?.id == container.id
        let isHovered = hoveredContainer == container.id
        let buttonSize = isCompact && !isActive ?
            (isHovered ? ContainerConstants.UI.compactButtonWidth + 4 : ContainerConstants.UI.compactButtonWidth) :
            ContainerConstants.UI.normalButtonWidth

        Button(action: {
            onContainerSelected(container)
        }) {
            Image(systemName: container.systemImage)
                .font(.system(size: isActive ? 14 : 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .frame(width: buttonSize, height: buttonSize)
                .grayscale(!isActive && !isHovered ? 0.5 : 0)
                .opacity(!isActive ? 0.5 : 1)
                .background(
                    !isCompact && isHovered
                        ? theme.invertedSolidWindowBackgroundColor.opacity(0.1)
                        : isActive
                        ? theme.invertedSolidWindowBackgroundColor.opacity(0.15)
                        : .clear
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(container.name)
        .accessibilityLabel(container.name)
        .animation(.easeOut(duration: 0.15), value: isActive || isHovered)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredContainer = isHovering ? container.id : nil
            }
        }
        .contextMenu {
            Menu("Ícone") {
                ForEach(SpaceIcon.groups) { group in
                    Section(group.title) {
                        ForEach(group.icons) { icon in
                            Button {
                                tabManager.renameContainer(
                                    container,
                                    name: container.name,
                                    emoji: container.emoji,
                                    iconSystemName: icon.name
                                )
                            } label: {
                                HStack {
                                    Label(icon.label, systemImage: icon.name)
                                    if container.systemImage == icon.name {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Edit Space") {
                dialogManager.show { id in
                    EditContainerModal(
                        container: container,
                        dismiss: { dialogManager.dismiss(id: id) }
                    )
                    .environmentObject(tabManager)
                }
            }
            Button("Delete Space") {
                dialogManager.confirm(
                    title: "Delete \"\(container.name)\"?",
                    message: "All tabs in this space will be permanently removed.",
                    icon: .spaceCards,
                    confirmLabel: "Delete",
                    variant: .destructive
                ) {
                    tabManager.deleteContainer(container)
                }
            }
            .disabled(containers.count == 1) // disabled to avoid crashes
        }
    }
}
