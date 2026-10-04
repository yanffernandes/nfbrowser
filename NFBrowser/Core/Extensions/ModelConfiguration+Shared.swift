import Foundation
import SwiftData

extension ModelConfiguration {
    /// Resolved database URL with automatic migration from legacy "Ora" location to "NFBrowser"
    static func databaseURL() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let newDir = appSupport.appendingPathComponent("NFBrowser", isDirectory: true)
        let newURL = newDir.appendingPathComponent("NFBrowserData.sqlite")
        let legacyDir = appSupport.appendingPathComponent("Ora", isDirectory: true)
        let legacyURL = legacyDir.appendingPathComponent("OraData.sqlite")

        try? fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)

        // Automatically migrate legacy database files if new database doesn't exist yet
        if !fileManager.fileExists(atPath: newURL.path), fileManager.fileExists(atPath: legacyURL.path) {
            for suffix in ["", "-shm", "-wal"] {
                let source = legacyDir.appendingPathComponent("OraData.sqlite\(suffix)")
                let dest = newDir.appendingPathComponent("NFBrowserData.sqlite\(suffix)")
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: dest)
                }
            }
        }

        return fileManager.fileExists(atPath: newURL.path) ? newURL : legacyURL
    }

    /// Shared model configuration for the main NFBrowser database
    static func oraDatabase(isPrivate: Bool = false) -> ModelConfiguration {
        if isPrivate {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            return ModelConfiguration(
                "OraData",
                schema: Schema([TabContainer.self, History.self, Download.self]),
                url: databaseURL()
            )
        }
    }

    /// Creates a ModelContainer using the standard NFBrowser database configuration
    static func createNFBrowserContainer(isPrivate: Bool = false) throws -> ModelContainer {
        try createOraContainer(isPrivate: isPrivate)
    }

    /// Creates a ModelContainer using the standard Ora database configuration
    static func createOraContainer(isPrivate: Bool = false) throws -> ModelContainer {
        return try ModelContainer(
            for: TabContainer.self, History.self, Download.self,
            configurations: oraDatabase(isPrivate: isPrivate)
        )
    }
}
