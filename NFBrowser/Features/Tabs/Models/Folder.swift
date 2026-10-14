import Foundation
import SwiftData

// MARK: - Folder

@Model
class Folder: ObservableObject, Identifiable {
    var id: UUID
    var name: String
    var isOpened: Bool

    @Relationship(inverse: \TabContainer.folders) var container: TabContainer
    @Relationship(deleteRule: .nullify) var tabs: [Tab] = []

    init(
        id: UUID = UUID(),
        name: String,
        isOpened: Bool = false,
        container: TabContainer
    ) {
        self.id = id
        self.name = name
        self.isOpened = isOpened
        self.container = container
    }
}
