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
        Group(title: "Spaces", icons: [
            Icon(name: "square.grid.2x2.fill", label: "General"),
            Icon(name: "checkmark.seal.fill", label: "Koncluí"),
            Icon(name: "sparkles", label: "XTYL"),
            Icon(name: "network", label: "Newar"),
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
        return switch normalizedName(for: name) {
        case "konclui": "checkmark.seal.fill"
        case "xtyl": "sparkles"
        case "newar": "network"
        case "secbrain": "brain.head.profile"
        case "webfi": "globe"
        case "cfk": "folder"
        default: "square.grid.2x2"
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
    var createdAt: Date
    var lastAccessedAt: Date

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

    @Relationship(deleteRule: .cascade) var tabs: [Tab] = []
    @Relationship(deleteRule: .cascade) var folders: [Folder] = []
    @Relationship var history: [History] = []

    init(
        id: UUID = UUID(),
        name: String = "Default",
        isActive: Bool = true,
        emoji: String = "",
        iconSystemName: String = ""
    ) {
        let nowDate = Date()
        self.id = id
        self.name = name
        self.emoji = emoji
        self.iconSystemName = iconSystemName
        self.createdAt = nowDate
        self.lastAccessedAt = nowDate
    }

    func reorderTabs(from: Tab, to: Tab) {
        let dir = from.order - to.order > 0 ? -1 : 1

        let tabOrder = self.tabs.sorted { dir == -1 ? $0.order > $1.order : $0.order < $1.order }

        var started = false
        for (index, tab) in tabOrder.enumerated() {
            if tab.id == from.id {
                started = true
            }
            if tab.id == to.id {
                break
            }
            if started {
                let currentTab = tab
                let nextTab = tabOrder[index + 1]

                let tempOrder = currentTab.order
                currentTab.order = nextTab.order
                nextTab.order = tempOrder
            }
        }
    }
}
