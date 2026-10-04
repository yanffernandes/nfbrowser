import Foundation
import SwiftData

enum SpaceIcon {
    struct Icon: Hashable, Identifiable {
        let name: String
        let label: String
        var id: String {
            name
        }
    }

    struct Group: Identifiable {
        let title: String
        let icons: [Icon]
        var id: String {
            title
        }
    }

    static let groups: [Group] = [
        Group(title: "Especiais", icons: [
            Icon(name: "checkmark.square.fill", label: "Check (Quadrado)"),
            Icon(name: "checkmark", label: "Check"),
            Icon(name: "checkmark.circle.fill", label: "Check (Círculo)"),
            Icon(name: "checkmark.seal.fill", label: "Check (Selo)"),
            Icon(name: "xmark.square.fill", label: "X (Quadrado)"),
            Icon(name: "xmark", label: "X"),
            Icon(name: "xmark.circle.fill", label: "X (Círculo)")
        ]),
        Group(title: "Spaces", icons: [
            Icon(name: "square.grid.2x2.fill", label: "Geral"),
            Icon(name: "sparkles", label: "Brilho"),
            Icon(name: "network", label: "Rede"),
            Icon(name: "brain.head.profile", label: "Secbrain"),
            Icon(name: "globe", label: "Web")
        ]),
        Group(title: "Work", icons: [
            Icon(name: "briefcase.fill", label: "Work"),
            Icon(name: "building.2.fill", label: "Company"),
            Icon(name: "chart.bar.fill", label: "Analytics"),
            Icon(name: "creditcard.fill", label: "Finance"),
            Icon(name: "envelope.fill", label: "Email"),
            Icon(name: "calendar", label: "Calendar"),
            Icon(name: "person.fill", label: "People"),
            Icon(name: "graduationcap.fill", label: "Learning"),
            Icon(name: "rocket.fill", label: "Projects")
        ]),
        Group(title: "Personal", icons: [
            Icon(name: "house.fill", label: "Home"),
            Icon(name: "heart.fill", label: "Health"),
            Icon(name: "leaf.fill", label: "Nature"),
            Icon(name: "airplane", label: "Travel"),
            Icon(name: "music.note", label: "Music"),
            Icon(name: "headphones", label: "Audio"),
            Icon(name: "camera.fill", label: "Photos"),
            Icon(name: "video.fill", label: "Video"),
            Icon(name: "bubble.left.and.bubble.right.fill", label: "Messages"),
            Icon(name: "phone.fill", label: "Phone")
        ]),
        Group(title: "Tools", icons: [
            Icon(name: "folder.fill", label: "Folder"),
            Icon(name: "books.vertical.fill", label: "Reading"),
            Icon(name: "cart.fill", label: "Shopping"),
            Icon(name: "bolt.fill", label: "Quick access"),
            Icon(name: "lock.fill", label: "Private"),
            Icon(name: "target", label: "Focus"),
            Icon(name: "shippingbox.fill", label: "Packages"),
            Icon(name: "newspaper.fill", label: "News"),
            Icon(name: "star.fill", label: "Favorites"),
            Icon(name: "flame.fill", label: "Ideas"),
            Icon(name: "clock.fill", label: "Time")
        ])
    ]

    static let options = groups.flatMap(\.icons)

    static func systemImage(for name: String) -> String {
        let norm = normalizedName(for: name)
        return switch norm {
        case "konclui", "conclui", "concluido", "done", "check": "checkmark.square.fill"
        case "xtyl", "x": "xmark.square.fill"
        case "newar": "network"
        case "secbrain": "brain.head.profile"
        case "webfi": "globe"
        case "cfk": "folder.fill"
        default: "square.grid.2x2.fill"
        }
    }

    static func sortOrder(for name: String) -> Int {
        switch normalizedName(for: name) {
        case "konclui": 0
        case "xtyl": 1
        case "newar": 2
        case "secbrain": 3
        case "webfi": 4
        case "cfk": 5
        default: 6
        }
    }

    private static func normalizedName(for name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "arc · ", with: "", options: [.caseInsensitive])
            .lowercased()
    }
}

// MARK: - TabContainer

@Model
class TabContainer: ObservableObject, Identifiable {
    var id: UUID
    var name: String
    var emoji: String
    var iconSystemName: String = ""
    var engine: String = BrowserEngineKind.webkit.rawValue
    var createdAt: Date
    var lastAccessedAt: Date

    var engineKind: BrowserEngineKind {
        get { BrowserEngineKind(rawValue: engine) ?? .webkit }
        set { engine = newValue.rawValue }
    }

    var systemImage: String {
        if SpaceIcon.options.contains(where: { $0.name == iconSystemName }) {
            return iconSystemName
        }
        let mappedIcon = SpaceIcon.systemImage(for: name)
        return SpaceIcon.options.contains(where: { $0.name == mappedIcon }) ? mappedIcon : "square.grid.2x2.fill"
    }

    var sidebarSortOrder: Int {
        SpaceIcon.sortOrder(for: name)
    }

    var idString: String {
        id.uuidString
    }

    static func stableSort(_ lhs: TabContainer, _ rhs: TabContainer) -> Bool {
        if lhs.sidebarSortOrder == rhs.sidebarSortOrder {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.sidebarSortOrder < rhs.sidebarSortOrder
    }

    @Relationship(deleteRule: .cascade) var tabs: [Tab] = []
    @Relationship(deleteRule: .cascade) var folders: [Folder] = []
    @Relationship var history: [History] = []

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isActive: Bool = true,
        emoji: String = "",
        iconSystemName: String = "",
        engine: BrowserEngineKind = .webkit
    ) {
        let nowDate = Date()
        self.id = id
        self.name = name
        self.emoji = emoji
        self.iconSystemName = iconSystemName
        self.engine = engine.rawValue
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
    }

    func reorderTabs(from: Tab, to: Tab) {
        guard from.id != to.id else { return }

        // Only reorder within the same tab section (normal, pinned, or fav)
        var sectionTabs = self.tabs
            .filter { $0.type == to.type }
            .sorted { $0.order > $1.order }

        guard let fromIndex = sectionTabs.firstIndex(where: { $0.id == from.id }),
              let toIndex = sectionTabs.firstIndex(where: { $0.id == to.id })
        else { return }

        let movedTab = sectionTabs.remove(at: fromIndex)
        sectionTabs.insert(movedTab, at: toIndex)

        // Assign clean, monotonic descending order numbers with generous spacing
        let total = sectionTabs.count
        for (index, tab) in sectionTabs.enumerated() {
            tab.order = (total - index) * 10
        }
    }
}
