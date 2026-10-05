import SwiftData
import SwiftUI

struct ContainerSwitcher: View {
    let onContainerSelected: (TabContainer) -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var dialogManager: DialogManager
    @Query var containers: [TabContainer]

    @State private var hoveredContainer: UUID?

    private let minButtonWidth: CGFloat = 22
    private let itemSpacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let count = orderedContainers.count
            let totalSpacing = CGFloat(max(0, count - 1)) * itemSpacing
            let totalRequiredWidth = CGFloat(count) * minButtonWidth + totalSpacing
            let needsScroll = count > 0 && totalRequiredWidth > availableWidth

            if needsScroll {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: itemSpacing) {
                            ForEach(orderedContainers, id: \.id) { container in
                                containerButton(for: container)
                                    .frame(width: 26, height: 28)
                                    .id(container.id)
                            }
                        }
                        .frame(height: 28)
                    }
                    .onAppear {
                        if let activeId = tabManager.activeContainer?.id {
                            proxy.scrollTo(activeId, anchor: .center)
                        }
                    }
                    .onChange(of: tabManager.activeContainer?.id) { _, newId in
                        if let newId {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                proxy.scrollTo(newId, anchor: .center)
                            }
                        }
                    }
                }
            } else if count == 1 {
                HStack {
                    if let first = orderedContainers.first {
                        containerButton(for: first)
                            .frame(maxWidth: 44, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                HStack(spacing: itemSpacing) {
                    ForEach(orderedContainers, id: \.id) { container in
                        containerButton(for: container)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(0)
        .frame(height: 28)
    }

    private var orderedContainers: [TabContainer] {
        containers.sorted(by: TabContainer.stableSort)
    }

    @ViewBuilder
    private func containerButton(for container: TabContainer) -> some View {
        let isActive = tabManager.activeContainer?.id == container.id
        let isHovered = hoveredContainer == container.id

        Button(action: {
            onContainerSelected(container)
        }) {
            Image(systemName: container.systemImage)
                .font(.system(size: isActive ? 13 : 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? theme.foreground : theme.mutedForeground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .grayscale(!isActive && !isHovered ? 0.35 : 0)
                .opacity(!isActive ? 0.65 : 1)
                .background(
                    isHovered
                        ? theme.invertedSolidWindowBackgroundColor.opacity(0.12)
                        : isActive
                        ? theme.invertedSolidWindowBackgroundColor.opacity(0.18)
                        : .clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    isActive
                        ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.invertedSolidWindowBackgroundColor.opacity(0.15), lineWidth: 1)
                        : nil
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(TactileBarButtonStyle())
        .help(container.name)
        .accessibilityLabel(container.name)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isActive || isHovered)
        .onHover { isHovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
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
