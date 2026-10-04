import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "Importer")

struct Root: Decodable {
    let sidebar: Sidebar
}

struct Sidebar: Decodable {
    let containers: [Container]
}

private struct ArcCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

struct ArcProfileReference: Decodable {
    let directoryBasename: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArcCodingKey.self)
        directoryBasename = Self.findDirectoryBasename(in: container)
    }

    private static func findDirectoryBasename(
        in container: KeyedDecodingContainer<ArcCodingKey>
    ) -> String? {
        if let name = try? container.decode(String.self, forKey: ArcCodingKey("directoryBasename")) {
            return name
        }
        if (try? container.decode(Bool.self, forKey: ArcCodingKey("default"))) == true {
            return "Default"
        }
        for key in container.allKeys {
            guard let nested = try? container.nestedContainer(keyedBy: ArcCodingKey.self, forKey: key),
                  let name = findDirectoryBasename(in: nested)
            else {
                continue
            }
            return name
        }
        return nil
    }
}

struct Container: Decodable {
    let global: Global?
    let spaces: [SpaceItem]?
    let items: [Item]?
    let topAppsContainerIDs: [TopAppsContainerID]?

    enum CodingKeys: String, CodingKey {
        case global
        case spaces
        case items
        case topAppsContainerIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        global = try container.decodeIfPresent(Global.self, forKey: .global)
        spaces = try container.decodeIfPresent([SpaceItem].self, forKey: .spaces)
        items = try container.decodeIfPresent([Item].self, forKey: .items)
        topAppsContainerIDs = try container.decodeIfPresent([TopAppsContainerID].self, forKey: .topAppsContainerIDs)
    }
}

struct Global: Decodable {}

enum SpaceItem: Decodable {
    case id(String)
    case custom(CustomInfo)

    struct CustomInfo: Decodable {
        let customInfo: IconWrapper
        let title: String?
        let id: String
        let containerIDs: [String]
        let profile: ArcProfileReference?
    }

    struct IconWrapper: Decodable {
        let iconType: IconType
    }

    struct IconType: Decodable {
        // swiftlint:disable:next identifier_name
        let emoji_v2: String?
        let emoji: Int?
        let icon: String?
    }

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let id = try? singleValue.decode(String.self)
        {
            self = .id(id)
        } else {
            self = try .custom(CustomInfo(from: decoder))
        }
    }
}

enum Item: Decodable {
    case id(String)
    case object(ItemObject)

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let id = try? singleValue.decode(String.self)
        {
            self = .id(id)
        } else {
            self = try .object(ItemObject(from: decoder))
        }
    }
}

struct ItemObject: Decodable {
    let id: String
    let originatingDevice: String?
    let createdAt: Double?
    let title: String?
    let data: ItemData?
    let parentID: String?
    let isUnread: Bool
    let childrenIds: [String]
}

struct ItemData: Decodable {
    let tab: TabData?
    let easel: EaselData?
    let itemContainer: ItemContainerData?
}

struct TabData: Decodable {
    let savedURL: String?
    let savedTitle: String?
    let savedMuteStatus: String?
    let activeTabBeforeCreationID: String?
    let timeLastActiveAt: Double?
}

struct EaselData: Decodable {
    let creatorID: String?
    let easelID: String?
    let shareStatus: String?
    let title: String?
    let timeLastActiveAt: Double?
}

struct ItemContainerData: Decodable {
    let containerType: ContainerType?

    struct ContainerType: Decodable {
        let spaceItems: [String: String]?
        let topApps: ArcProfileReference?
    }
}

enum TopAppsContainerID: Decodable {
    case id(String)
    case object(TopAppsObject)

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let id = try? singleValue.decode(String.self)
        {
            self = .id(id)
        } else {
            self = try .object(TopAppsObject(from: decoder))
        }
    }
}

struct TopAppsObject: Decodable {
    let id: String?
    // Add more fields as needed based on actual JSON structure
}

func getRoot() -> Root? {
    let url = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Arc/StorableSidebar.json")
        .expandingTildeInPath
    )

    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Root.self, from: data)
    } catch {
        logger.error("Decoding failed: \(String(describing: error), privacy: .public)")
        return nil
    }
}

struct CleanSpace {
    var sourceID: String
    var emoji: String?
    var icon: String?
    var title: String?
    var profileDirectoryBasename: String?
    var containerIDs: Set<String>  = []
    var container: TabContainer?
}

struct CleanTab {
    var title: String
    var urlString: String
    var id: String
    var parentID: String
}

struct Result {
    var cleanSpaces: [CleanSpace]
    var cleanTabs: [CleanTab]
    var favs: Set<String> = []
    var parentIDs: [String: String] = [:]
    var favoriteProfileByContainerID: [String: String] = [:]
}

func inspectItems(_ root: Root) -> Result {
    var cleanSpaces: [CleanSpace] = []
    var cleanTabs: [CleanTab] = []
    var topIds: [String] = []
    var parentIDs: [String: String] = [:]
    var favoriteProfileByContainerID: [String: String] = [:]

    for container in root.sidebar.containers {
        if let spaces = container.spaces {
            for item in spaces {
                switch item {
                case let .custom(customInfo):
                    var cleanSpace = CleanSpace(
                        sourceID: customInfo.id,
                        emoji: customInfo.customInfo.iconType.emoji_v2,
                        icon: customInfo.customInfo.iconType.icon,
                        title: customInfo.title,
                        profileDirectoryBasename: customInfo.profile?.directoryBasename,
                        containerIDs: []
                    )
                    for cid in customInfo.containerIDs {
                        cleanSpace.containerIDs
                            .insert(cid)
                    }
                    cleanSpace.containerIDs
                        .insert(customInfo.id)

                    cleanSpaces.append(cleanSpace)
                case let .id(id):
                    logger.debug("Space ID: \(id)")
                }
            }
        } else {
            logger.debug("No spaces")
        }

        // Inspect items with detailed output
        if let items = container.items {
            var idCount = 0
            var objectCount = 0
            for (itemIndex, item) in items.enumerated() {
                logger.debug("Item \(itemIndex + 1):")
                switch item {
                case let .id(id):
                    idCount += 1
                    logger.debug("ID: \(id)")
                case let .object(itemObject):
                    objectCount += 1
                    if let parentID = itemObject.parentID {
                        parentIDs[itemObject.id] = parentID
                    }

                    if let data = itemObject.data {
                        if let profileDirectoryBasename = data.itemContainer?.containerType?.topApps?
                            .directoryBasename
                        {
                            favoriteProfileByContainerID[itemObject.id] = profileDirectoryBasename
                        }
                        if let tab = data.tab {
                            if let parentID = itemObject.parentID, let urlString = tab.savedURL {
                                cleanTabs.append(
                                    CleanTab(
                                        title: tab.savedTitle ?? "New Tab",
                                        urlString: urlString,
                                        id: itemObject.id,
                                        parentID: parentID
                                    )
                                )
                            }
                        }
                    }
                }
            }
            logger.debug("    Total: \(idCount) IDs, \(objectCount) objects")
        }

        // Inspect topAppsContainerIDs
        if let topApps = container.topAppsContainerIDs {
            for topApp in topApps {
                switch topApp {
                case let .id(id):
                    topIds.append(id)
                case let .object(obj):
                    logger.debug("TopApp Object: id=\(obj.id ?? "n/a")")
                }
            }
        }
    }
    var result = Result(
        cleanSpaces: cleanSpaces,
        cleanTabs: cleanTabs,
        parentIDs: parentIDs,
        favoriteProfileByContainerID: favoriteProfileByContainerID
    )
    for tid in topIds {
        result.favs.insert(tid)
    }

    return result
}
