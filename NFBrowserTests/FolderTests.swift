import Foundation
@testable import NFBrowser
import SwiftData
import Testing

struct FolderTests {
    @Test @MainActor func createsFolderInContainer() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let folder = tabManager.createFolder(name: "Research", in: space)
        #expect(space.folders.count == 1)
        #expect(folder.name == "Research")
        #expect(folder.isOpened == false)
    }

    @Test @MainActor func movesTabInAndOutOfFolder() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)
        let historyManager = HistoryManager(modelContainer: container, modelContext: context)

        let folder = tabManager.createFolder(name: "Projects", in: space)
        let tab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com")!,
                historyManager: historyManager,
                isPrivate: true
            )
        )

        #expect(tab.folder == nil)
        #expect(folder.tabs.isEmpty)

        // Move into folder
        tabManager.moveTab(tab, to: folder)
        #expect(tab.folder?.id == folder.id)

        // Remove from folder
        tabManager.moveTab(tab, to: nil)
        #expect(tab.folder == nil)
    }

    @Test @MainActor func togglesAndRenamesFolder() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let folder = tabManager.createFolder(name: "Old Name", in: space)
        #expect(!folder.isOpened)

        tabManager.toggleFolder(folder)
        #expect(folder.isOpened)

        tabManager.renameFolder(folder, to: "New Name")
        #expect(folder.name == "New Name")
    }

    @Test @MainActor func deletesFolderAndKeepsTabs() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)
        let historyManager = HistoryManager(modelContainer: container, modelContext: context)

        let folder = tabManager.createFolder(name: "Temp", in: space)
        let tab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/keep")!,
                historyManager: historyManager,
                isPrivate: true
            )
        )
        tabManager.moveTab(tab, to: folder)

        // Delete folder but keep tabs
        tabManager.deleteFolder(folder, closeContainedTabs: false)

        #expect(space.folders.isEmpty)
        #expect(tab.folder == nil)
        #expect(space.tabs.contains(where: { $0.id == tab.id }))
    }

    @Test @MainActor func deletesFolderAndClosesTabs() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)
        let historyManager = HistoryManager(modelContainer: container, modelContext: context)

        let folder = tabManager.createFolder(name: "Ephemeral", in: space)
        let tab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/close")!,
                historyManager: historyManager,
                isPrivate: true
            )
        )
        tabManager.moveTab(tab, to: folder)

        // Delete folder and close contained tabs
        tabManager.deleteFolder(folder, closeContainedTabs: true)

        #expect(space.folders.isEmpty)
        #expect(!space.tabs.contains(where: { $0.id == tab.id }))
    }
}
