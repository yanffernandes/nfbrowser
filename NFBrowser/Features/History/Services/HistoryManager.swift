import Foundation
import os.log
import SwiftData

private let logger = Logger(subsystem: "com.orabrowser.ora", category: "HistoryManager")

@MainActor
class HistoryManager: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    @Published var historyRevision: Int = 0

    init(modelContainer: ModelContainer, modelContext: ModelContext) {
        self.modelContainer = modelContainer
        self.modelContext = modelContext
    }

    func record(
        title: String,
        url: URL,
        faviconURL: URL? = nil,
        faviconLocalFile: URL? = nil,
        container: TabContainer
    ) {
        let urlString = url.absoluteString
        let containerId = container.id

        // Keep history entries scoped to a space so visits from different spaces
        // do not overwrite each other or become unreachable from space filters.
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { history in
                history.urlString == urlString && history.container?.id == containerId
            },
            sortBy: [.init(\.lastAccessedAt, order: .reverse)]
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.visitCount += 1
            existing.lastAccessedAt = Date() // update last visited time
            if !title.isEmpty {
                existing.title = title
            }
        } else {
            let now = Date()
            let defaultFaviconURL = FaviconService.shared.faviconURL(for: url.host ?? "")
            let resolvedFaviconURL = faviconURL ?? defaultFaviconURL ?? url
            let effectiveTitle = title.isEmpty ? (url.host ?? url.absoluteString) : title
            modelContext.insert(History(
                url: url,
                title: effectiveTitle,
                faviconURL: resolvedFaviconURL,
                faviconLocalFile: faviconLocalFile,
                createdAt: now,
                lastAccessedAt: now,
                visitCount: 1,
                container: container
            ))
        }

        try? modelContext.save()
        historyRevision += 1
    }

    func search(_ text: String, activeContainerId: UUID) -> [History] {
        searchAll(text, containerId: activeContainerId)
    }

    func searchAll(_ text: String = "", containerId: UUID? = nil) -> [History] {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        let descriptor: FetchDescriptor<History>
        if let containerId {
            descriptor = FetchDescriptor<History>(
                predicate: #Predicate { $0.container?.id == containerId },
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<History>(
                sortBy: [SortDescriptor(\.lastAccessedAt, order: .reverse)]
            )
        }

        do {
            let histories = try modelContext.fetch(descriptor)

            guard !trimmedText.isEmpty else {
                return histories
            }

            return histories.filter { history in
                history.urlString.localizedStandardContains(trimmedText) ||
                    history.title.localizedStandardContains(trimmedText)
            }
        } catch {
            logger.error("Error fetching history: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func deleteItem(_ item: History) {
        modelContext.delete(item)
        try? modelContext.save()
        historyRevision += 1
    }

    func clearContainerHistory(_ container: TabContainer) {
        let containerId = container.id
        let descriptor = FetchDescriptor<History>(
            predicate: #Predicate { $0.container?.id == containerId }
        )

        do {
            let histories = try modelContext.fetch(descriptor)

            for history in histories {
                modelContext.delete(history)
            }

            try modelContext.save()
            historyRevision += 1
        } catch {
            logger.error("Failed to clear history for container \(container.id): \(error.localizedDescription)")
        }
    }

    func clearAllHistory() {
        let descriptor = FetchDescriptor<History>()
        do {
            let histories = try modelContext.fetch(descriptor)
            for history in histories {
                modelContext.delete(history)
            }
            try modelContext.save()
            historyRevision += 1
        } catch {
            logger.error("Failed to clear all history: \(error.localizedDescription)")
        }
    }
}
