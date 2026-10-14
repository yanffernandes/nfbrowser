import Foundation
@testable import NFBrowser
import SwiftData
import Testing

struct HistoryManagerTests {
    @Test @MainActor func recordsAndUpdatesHistoryEntry() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Work")
        context.insert(space)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        let testURL = URL(string: "https://example.com/docs")!

        // First record
        historyManager.record(title: "Documentation", url: testURL, container: space)
        var results = historyManager.searchAll(containerId: space.id)
        #expect(results.count == 1)
        #expect(results.first?.title == "Documentation")
        #expect(results.first?.visitCount == 1)

        // Second visit updates visitCount
        historyManager.record(title: "Docs Updated", url: testURL, container: space)
        results = historyManager.searchAll(containerId: space.id)
        #expect(results.count == 1)
        #expect(results.first?.visitCount == 2)
        #expect(results.first?.title == "Docs Updated")
    }

    @Test @MainActor func searchesByTitleAndURL() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Personal")
        context.insert(space)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        historyManager.record(title: "GitHub Repository", url: URL(string: "https://github.com/nfbrowser")!, container: space)
        historyManager.record(title: "Apple Developer", url: URL(string: "https://developer.apple.com")!, container: space)

        let search1 = historyManager.searchAll("github", containerId: space.id)
        #expect(search1.count == 1)
        #expect(search1.first?.title == "GitHub Repository")

        let search2 = historyManager.searchAll("apple.com", containerId: space.id)
        #expect(search2.count == 1)
        #expect(search2.first?.title == "Apple Developer")

        let searchEmpty = historyManager.searchAll("nonexistent", containerId: space.id)
        #expect(searchEmpty.isEmpty)
    }

    @Test @MainActor func deletesIndividualItem() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space = TabContainer(name: "Personal")
        context.insert(space)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        historyManager.record(title: "Page A", url: URL(string: "https://a.example")!, container: space)
        historyManager.record(title: "Page B", url: URL(string: "https://b.example")!, container: space)

        var results = historyManager.searchAll(containerId: space.id)
        #expect(results.count == 2)

        if let itemToDelete = results.first(where: { $0.title == "Page A" }) {
            historyManager.deleteItem(itemToDelete)
        }

        results = historyManager.searchAll(containerId: space.id)
        #expect(results.count == 1)
        #expect(results.first?.title == "Page B")
    }

    @Test @MainActor func clearsContainerHistoryOnly() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space1 = TabContainer(name: "Space 1")
        let space2 = TabContainer(name: "Space 2")
        context.insert(space1)
        context.insert(space2)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        historyManager.record(title: "Item 1", url: URL(string: "https://item1.example")!, container: space1)
        historyManager.record(title: "Item 2", url: URL(string: "https://item2.example")!, container: space2)

        historyManager.clearContainerHistory(space1)

        #expect(historyManager.searchAll(containerId: space1.id).isEmpty)
        #expect(historyManager.searchAll(containerId: space2.id).count == 1)
    }

    @Test @MainActor func clearsAllHistoryAcrossSpaces() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let space1 = TabContainer(name: "Space 1")
        let space2 = TabContainer(name: "Space 2")
        context.insert(space1)
        context.insert(space2)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        historyManager.record(title: "Item 1", url: URL(string: "https://item1.example")!, container: space1)
        historyManager.record(title: "Item 2", url: URL(string: "https://item2.example")!, container: space2)

        historyManager.clearAllHistory()

        #expect(historyManager.searchAll().isEmpty)
    }

    @Test func dateGroupClassifiesCorrectly() {
        let now = Date()
        #expect(HistoryDateGroup.group(for: now) == .today)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        #expect(HistoryDateGroup.group(for: yesterday) == .yesterday)

        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: now)!
        #expect(HistoryDateGroup.group(for: fourDaysAgo) == .past7Days)

        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: now)!
        #expect(HistoryDateGroup.group(for: twentyDaysAgo) == .past30Days)

        let twoMonthsAgo = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        #expect(HistoryDateGroup.group(for: twoMonthsAgo) == .older)
    }
}
