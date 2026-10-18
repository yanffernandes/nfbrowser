import AppKit
import Foundation
import WebKit

struct ExtensionItem: Identifiable, Equatable {
    let id: String
    var displayName: String
    var version: String
    var extensionDescription: String
    var iconURL: URL?
    var isEnabled: Bool
    let directoryURL: URL
    var context: WKWebExtensionContext?

    static func == (lhs: ExtensionItem, rhs: ExtensionItem) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled && lhs.version == rhs.version
    }
}
