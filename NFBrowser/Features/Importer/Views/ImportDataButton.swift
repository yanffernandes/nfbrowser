import AppKit
import Security
import SwiftData
import SwiftUI
import WebKit

@MainActor
private enum ArcImportProgress {
    static var isRunning = false
    static var launchRequestConsumed = false
}

struct ArcImportController: View {
    let tabManager: TabManager
    let historyManager: HistoryManager
    let downloadManager: DownloadManager
    let window: NSWindow?

    @State private var progressMessage: String?

    private static let arcImportPreferenceKey = "Ora.ArcImport.completed.v1"

    private struct ImportCounts {
        var spaces = 0
        var tabs = 0
        var cookies = 0
        var passwords = 0
        var duplicatePasswords = 0
        var failedPasswords = 0
        var passwordSaveFailureStatus: OSStatus?
        var downloads = 0
    }

    private func importArc() {
        progressMessage = "Reading Arc profiles…"
        Task {
            await performArcImport()
        }
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private func performArcImport() async {
        guard !ArcImportProgress.isRunning else { return }
        if UserDefaults.standard.bool(forKey: Self.arcImportPreferenceKey) {
            let alert = NSAlert()
            alert.messageText = "Re-import from Arc?"
            alert.informativeText = "NF Browser has already imported Arc data on this Mac. Would you like to re-import and update your Arc spaces, tabs, cookies, and passwords?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Re-import")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                progressMessage = nil
                return
            }
        }

        ArcImportProgress.isRunning = true
        defer { ArcImportProgress.isRunning = false }

        do {
            progressMessage = "Reading Arc profiles and browser data…"
            await Task.yield()
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try ArcBrowserDataImporter.loadSnapshot()
            }.value

            progressMessage = "Preparing Arc spaces and tabs…"
            await Task.yield()
            let sidebarResult = getRoot().map(inspectItems)
            let dataContainerID = ArcImportIdentity.stableUUID(
                for: "com.orabrowser.app:arc-import:root"
            )
            var existingContainers = try tabManager.modelContext.fetch(FetchDescriptor<TabContainer>())
            let dataContainer: TabContainer
            if let existing = existingContainers.first(where: { $0.id == dataContainerID }) {
                dataContainer = existing
            } else {
                dataContainer = TabContainer(id: dataContainerID, name: "Arc Imported")
                tabManager.modelContext.insert(dataContainer)
                existingContainers.append(dataContainer)
            }
            dataContainer.lastAccessedAt = .distantPast
            try tabManager.modelContext.save()

            var counts = ImportCounts()
            if let sidebarResult {
                progressMessage = "Importing Arc spaces and tabs…"
                let sidebarCounts = try await importSidebar(
                    sidebarResult,
                    dataContainer: dataContainer,
                    existingContainers: existingContainers
                ) { processed, total in
                    progressMessage = "Importing Arc tabs: \(processed.formatted()) / \(total.formatted())"
                }
                counts.spaces = sidebarCounts.spaces
                counts.tabs = sidebarCounts.tabs
            }

            progressMessage = "Saving Arc passwords…"
            await Task.yield()
            let passwordCounts = PasswordManagerService.shared.importCredentials(
                snapshot.passwords,
                containerID: dataContainer.id
            )
            counts.passwords = passwordCounts.imported
            counts.duplicatePasswords = passwordCounts.skipped
            counts.failedPasswords = passwordCounts.failed
            counts.passwordSaveFailureStatus = passwordCounts.firstFailureStatus

            progressMessage = "Importing Arc download history…"
            await Task.yield()
            counts.downloads = importDownloads(snapshot.downloads)
            try downloadManager.modelContext.save()

            counts.cookies = await importCookies(snapshot.cookies) { processed, total in
                progressMessage = "Importing Arc cookies: \(processed.formatted()) / \(total.formatted())"
            }

            try tabManager.modelContext.save()
            try downloadManager.modelContext.save()
            downloadManager.refreshRecentDownloads()
            if sidebarResult != nil {
                UserDefaults.standard.set(true, forKey: Self.arcImportPreferenceKey)
            }
            progressMessage = nil

            var message = """
            Spaces and tabs: \(counts.spaces) spaces, \(counts.tabs) tabs
            Cookies: \(counts.cookies)
            Saved passwords: \(counts.passwords) of \(snapshot.passwords.count) readable Arc entries
            Downloads: \(counts.downloads)
            Arc profiles scanned: \(snapshot.profileCount)
            """

            if counts.duplicatePasswords > 0 {
                message += "\nExisting passwords skipped: \(counts.duplicatePasswords)"
            }
            if counts.failedPasswords > 0 || snapshot.skippedPasswords > 0 {
                message += "\nPasswords skipped: \(counts.failedPasswords + snapshot.skippedPasswords)"
            }
            if let status = counts.passwordSaveFailureStatus {
                message += "\nPassword Keychain error code: \(status)"
            }
            if snapshot.skippedCookies > 0 {
                message += "\nCookies skipped: \(snapshot.skippedCookies)"
            }
            if snapshot.databaseFailures > 0 {
                message += "\nArc database files that could not be read: \(snapshot.databaseFailures)"
            }
            if sidebarResult == nil {
                message += "\nArc's sidebar could not be read, so spaces and tabs were not imported. You can run the import again after fixing the sidebar reader."
            }

            message += """


            NF Browser keeps one shared cookie store across its Spaces. When Arc had separate values for the same cookie in different profiles, NF Browser kept the active Arc profile's value. Partitioned cookies and Arc site storage, extensions, and browser-only settings cannot be moved into NF Browser.
            """

            showAlert(title: "Arc data imported", message: message)
        } catch {
            progressMessage = nil
            showAlert(
                title: "Arc import stopped",
                message: "NF Browser couldn't finish the Arc import. Any completed batches were saved; you can run the import again and NF Browser will reuse them without duplicating tabs, passwords, or downloads."
            )
        }
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private func importSidebar(
        _ result: Result,
        dataContainer: TabContainer,
        existingContainers: [TabContainer],
        progress: (Int, Int) -> Void
    ) async throws -> (spaces: Int, tabs: Int) {
        let spaces = result.cleanSpaces
        var containers: [TabContainer] = []
        var containersByID = Dictionary(
            existingContainers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (index, space) in spaces.enumerated() {
            let title = displaySpaceName(space.title, index: index)
            let spaceID = ArcImportIdentity.stableUUID(
                for: "com.orabrowser.app:arc-import:space:\(space.sourceID)"
            )
            let container: TabContainer
            if let existing = containersByID[spaceID] {
                container = existing
            } else {
                container = TabContainer(
                    id: spaceID,
                    name: title
                )
                tabManager.modelContext.insert(container)
                containersByID[spaceID] = container
            }
            container.name = title
            container.emoji = ""
            container.lastAccessedAt = .distantPast
            containers.append(container)
        }

        var existingTabsByID = Dictionary(
            existingContainers.flatMap(\.tabs).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var arcTabIDs = Set<UUID>()

        func spaceIndex(for originalParentID: String) -> Int? {
            var currentID = originalParentID
            var visited = Set<String>()

            while visited.insert(currentID).inserted {
                if let index = spaces.firstIndex(where: { $0.containerIDs.contains(currentID) }) {
                    return index
                }
                guard let parentID = result.parentIDs[currentID] else { return nil }
                currentID = parentID
            }

            return nil
        }

        var seenTabs = Set<String>()
        for (index, sourceTab) in result.cleanTabs.enumerated() {
            guard seenTabs.insert(sourceTab.id).inserted else { continue }
            guard let url = URL(string: sourceTab.urlString),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else {
                continue
            }

            let importedID = ArcImportIdentity.stableUUID(
                for: "com.orabrowser.app:arc-import:tab:\(sourceTab.id)"
            )
            arcTabIDs.insert(importedID)

            let isFavorite = result.favs.contains(sourceTab.id) || result.favs.contains(sourceTab.parentID)
            let destination: TabContainer
            if isFavorite,
               let profileDirectoryBasename = result.favoriteProfileByContainerID[sourceTab.parentID],
               let favoriteSpaceIndex = spaces.firstIndex(where: {
                   $0.profileDirectoryBasename == profileDirectoryBasename
               }),
               containers.indices.contains(favoriteSpaceIndex)
            {
                destination = containers[favoriteSpaceIndex]
            } else if isFavorite {
                // Some Arc profiles have favorites but no corresponding Arc Space in the sidebar.
                dataContainer.name = "Other Arc favorites"
                destination = dataContainer
            } else if let index = spaceIndex(for: sourceTab.parentID), containers.indices.contains(index) {
                destination = containers[index]
            } else {
                destination = dataContainer
            }

            if let existing = existingTabsByID[importedID] {
                if existing.container.id != destination.id {
                    existing.container.tabs.removeAll { $0.id == importedID }
                    existing.container = destination
                    destination.tabs.append(existing)
                }
                existing.type = isFavorite ? .fav : (existing.type == .pinned ? .pinned : .normal)
                existing.savedURL = isFavorite ? url : nil
                if existing.lastAccessedAt == .distantPast {
                    existing.lastAccessedAt = Date()
                }
                if existing.faviconLocalFile.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true {
                    existing.setFavicon()
                }
                continue
            }

            let importedTab = Tab(
                id: importedID,
                url: url,
                title: sourceTab.title,
                container: destination,
                type: isFavorite ? .fav : .normal,
                order: destination.tabs.count + 1,
                historyManager: historyManager,
                downloadManager: downloadManager,
                tabManager: tabManager,
                isPrivate: false
            )
            importedTab.savedURL = isFavorite ? url : nil
            importedTab.lastAccessedAt = Date()
            tabManager.modelContext.insert(importedTab)
            destination.tabs.append(importedTab)
            existingTabsByID[importedID] = importedTab
            importedTab.setFavicon()

            if (index + 1).isMultiple(of: 200) {
                try tabManager.modelContext.save()
                progress(index + 1, result.cleanTabs.count)
                await Task.yield()
            }
        }

        let importedSpaceCount = containers.count + (dataContainer.tabs.isEmpty ? 0 : 1)
        if dataContainer.tabs.isEmpty {
            tabManager.modelContext.delete(dataContainer)
        }
        try tabManager.modelContext.save()
        progress(result.cleanTabs.count, result.cleanTabs.count)
        return (importedSpaceCount, arcTabIDs.count)
    }

    private func displaySpaceName(_ title: String?, index: Int) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let unprefixedTitle = trimmedTitle.replacingOccurrences(
            of: "^Arc\\s*[·•-]\\s*",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let normalizedTitle = unprefixedTitle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return switch normalizedTitle.lowercased() {
        case "konclui": "Koncluí"
        case "xtyl": "XTYL"
        case "newar": "Newar"
        case "secbrain": "SecBrain"
        case "webfi": "Webfi"
        case "cfk": "CFK"
        default: unprefixedTitle.isEmpty ? "Arc Space \(index + 1)" : unprefixedTitle
        }
    }

    @MainActor
    private func importCookies(
        _ records: [ArcCookieImportRecord],
        progress: (Int, Int) -> Void
    ) async -> Int {
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        var importableCookies: [HTTPCookie] = []
        var importedKeys = Set<String>()

        for record in records {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: record.domain,
                .path: record.path,
                .name: record.name,
                .value: record.value,
                .version: "0"
            ]
            if let expiresAt = record.expiresAt {
                properties[.expires] = expiresAt
            } else {
                properties[.discard] = "TRUE"
            }
            if record.isSecure {
                properties[.secure] = "TRUE"
            }
            if record.isHTTPOnly {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }

            guard let cookie = HTTPCookie(properties: properties) else { continue }
            importableCookies.append(cookie)
            importedKeys.insert(cookieIdentity(cookie))
        }

        let batchSize = 100
        for start in stride(from: 0, to: importableCookies.count, by: batchSize) {
            let end = min(start + batchSize, importableCookies.count)
            let group = DispatchGroup()
            for cookie in importableCookies[start ..< end] {
                group.enter()
                cookieStore.setCookie(cookie) {
                    group.leave()
                }
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    group.wait()
                    continuation.resume()
                }
            }
            progress(end, importableCookies.count)
            await Task.yield()
        }

        let storedCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        return storedCookies.filter { importedKeys.contains(cookieIdentity($0)) }.count
    }

    private func cookieIdentity(_ cookie: HTTPCookie) -> String {
        "\(cookie.domain.lowercased())\u{0}\(cookie.name)\u{0}\(cookie.path)"
    }

    private func importDownloads(_ records: [ArcDownloadImportRecord]) -> Int {
        let existing = (try? downloadManager.modelContext.fetch(FetchDescriptor<Download>())) ?? []
        var existingKeys = Set(existing.map(downloadIdentity))
        let arcDownloadKeys = Set(records.map {
            "\($0.url.absoluteString)|\($0.fileName)|\($0.startedAt.timeIntervalSince1970)"
        })
        for record in records {
            let key = "\(record.url.absoluteString)|\(record.fileName)|\(record.startedAt.timeIntervalSince1970)"
            guard existingKeys.insert(key).inserted else { continue }

            let download = Download(
                originalURL: record.url,
                fileName: record.fileName,
                fileSize: record.fileSize,
                downloadedBytes: record.downloadedBytes,
                createdAt: record.startedAt
            )
            if !record.targetPath.isEmpty,
               FileManager.default.fileExists(atPath: record.targetPath)
            {
                download.destinationURL = URL(fileURLWithPath: record.targetPath)
            }
            download.status = switch record.state {
            case 1: .completed
            case 2: .cancelled
            default: .failed
            }
            if download.status == .completed {
                download.progress = 1
                download.displayProgress = 1
                download.completedAt = record.completedAt
            } else {
                download.error = "Imported from Arc; the download did not finish there."
            }

            downloadManager.modelContext.insert(download)
        }
        return arcDownloadKeys.intersection(existingKeys).count
    }

    private func downloadIdentity(_ download: Download) -> String {
        "\(download.originalURLString)|\(download.fileName)|\(download.createdAt.timeIntervalSince1970)"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let progressMessage {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progressMessage)
                        .font(.callout)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .importArcData)) { notification in
            guard let window,
                  let sourceWindow = notification.object as? NSWindow,
                  sourceWindow === window
            else {
                return
            }
            importArc()
        }
        .onAppear {
            #if DEBUG
                guard !ArcImportProgress.launchRequestConsumed,
                      ProcessInfo.processInfo.arguments.contains("--import-arc")
                else {
                    return
                }
                ArcImportProgress.launchRequestConsumed = true
                importArc()
            #endif
        }
    }
}

struct ImportDataButton: View {
    var body: some View {
        Menu("Import Data") {
            Button("Arc") {
                guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                NotificationCenter.default.post(name: .importArcData, object: window)
            }

            Button("Safari") {
                // Safari import is not implemented yet.
            }
            .disabled(true)

            Button("Chrome") {
                // Chrome import is not implemented yet.
            }
            .disabled(true)
        }
    }
}
