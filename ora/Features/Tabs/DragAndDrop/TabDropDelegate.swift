import AppKit
import SwiftUI

extension Array where Element: Hashable {
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct TabDropDelegate: DropDelegate {
    let item: Tab  // to
    @Binding var draggedItem: UUID?

    let targetSection: TabSection

    func dropEntered(info: DropInfo) {
        if let uuid = draggedItem {
            handleDrop(uuid: uuid)
            return
        }

        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            if let string = object as? String,
               let uuid = UUID(uuidString: string)
            {
                DispatchQueue.main.async {
                    self.handleDrop(uuid: uuid)
                }
            }
        }
    }

    private func handleDrop(uuid: UUID) {
        guard uuid != self.item.id else { return }

        var from = self.item.container.tabs.first(where: { $0.id == uuid })

        if from == nil {
            for container in self.item.container.tabs.compactMap(\.container).unique() {
                if let foundTab = container.tabs.first(where: { $0.id == uuid }) {
                    from = foundTab
                    break
                }
            }
        }

        guard let from else { return }

        performHapticFeedback(pattern: .alignment)

        withAnimation(
            .spring(
                response: 0.25,
                dampingFraction: 0.82
            )
        ) {
            if isInSameSection(
                from: from,
                to: self.item
            ) {
                self.item.container
                    .reorderTabs(
                        from: from,
                        to: self.item
                    )
            } else {
                moveTabBetweenSections(from: from, to: self.item)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        .init(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        if let uuid = draggedItem {
            handleDrop(uuid: uuid)
        }
        try? self.item.container.modelContext?.save()
        draggedItem = nil
        return true
    }
}
