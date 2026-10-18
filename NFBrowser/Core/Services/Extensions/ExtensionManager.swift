import AppKit
import Foundation
import WebKit

@MainActor
final class ExtensionManager: NSObject, ObservableObject {
    static let shared = ExtensionManager()

    let webExtensionController = WKWebExtensionController()

    @Published private(set) var installedExtensions: [ExtensionItem] = []
    @Published var isInstalling: Bool = false
    @Published var installStatusMessage: String? = nil
    @Published var activePopupExtension: ExtensionItem? = nil

    private let disabledExtensionsKey = "extensions.disabled.ids"

    var extensionsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NFBrowser/Extensions", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var disabledIds: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: disabledExtensionsKey) ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: disabledExtensionsKey)
        }
    }

    override private init() {
        super.init()
        webExtensionController.delegate = self
    }

    // MARK: - Lifecycle & Loading

    func loadInstalledExtensions() {
        Task { [weak self] in
            guard let self else { return }
            let dir = self.extensionsDirectory

            guard let enumerator = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            var loadedItems: [ExtensionItem] = []

            for folderURL in enumerator {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }

                let manifestURL = folderURL.appendingPathComponent("manifest.json")
                guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                    continue
                }

                let extId = folderURL.lastPathComponent

                if let item = await self.loadExtension(from: folderURL, id: extId) {
                    loadedItems.append(item)
                }
            }

            self.installedExtensions = loadedItems
        }
    }

    func loadExtension(from folderURL: URL, id: String) async -> ExtensionItem? {
        do {
            let ext = try await WKWebExtension(resourceBaseURL: folderURL)
            let context = WKWebExtensionContext(for: ext)

            // Automatically grant requested permissions for seamless operation
            for permission in ext.requestedPermissions {
                context.setPermissionStatus(.grantedExplicitly, for: permission)
            }
            for matchPattern in ext.requestedPermissionMatchPatterns {
                context.setPermissionStatus(.grantedExplicitly, for: matchPattern)
            }

            let isEnabled = !disabledIds.contains(id)

            if isEnabled {
                do {
                    try await webExtensionController.load(context)
                } catch {
                    print("[ExtensionManager] Failed to load context for \(id): \(error)")
                }
            }

            let iconURL = findBestIconURL(in: folderURL)

            return ExtensionItem(
                id: id,
                displayName: ext.displayName ?? id,
                version: ext.version ?? "1.0",
                extensionDescription: ext.displayDescription ?? "",
                iconURL: iconURL,
                isEnabled: isEnabled,
                directoryURL: folderURL,
                context: context
            )
        } catch {
            print("[ExtensionManager] Error initializing extension from \(folderURL.path): \(error)")
            return nil
        }
    }

    private func findBestIconURL(in folderURL: URL) -> URL? {
        let manifestURL = folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let icons = json["icons"] as? [String: String] {
            // Find largest icon size
            let sortedKeys = icons.keys.compactMap { Int($0) }.sorted(by: >)
            for key in sortedKeys {
                if let path = icons[String(key)] {
                    let iconFile = folderURL.appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: iconFile.path) {
                        return iconFile
                    }
                }
            }
            if let first = icons.values.first {
                let iconFile = folderURL.appendingPathComponent(first)
                if FileManager.default.fileExists(atPath: iconFile.path) {
                    return iconFile
                }
            }
        }

        if let action = (json["action"] ?? json["browser_action"]) as? [String: Any],
           let icons = action["default_icon"] as? [String: String] {
            if let first = icons.values.first {
                let iconFile = folderURL.appendingPathComponent(first)
                if FileManager.default.fileExists(atPath: iconFile.path) {
                    return iconFile
                }
            }
        }

        return nil
    }

    // MARK: - Installation

    func installFromChromeWebStore(extensionId: String, name: String? = nil) async throws {
        isInstalling = true
        installStatusMessage = "Baixando \(name ?? "extensão") da Chrome Web Store..."

        defer {
            isInstalling = false
            installStatusMessage = nil
        }

        let targetDir = extensionsDirectory.appendingPathComponent(extensionId)
        try await ChromeWebStoreService.shared.downloadAndExtract(
            extensionId: extensionId,
            destinationDirectory: targetDir
        )

        installStatusMessage = "Carregando extensão no WebKit..."

        if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
            let old = installedExtensions[index]
            if let oldContext = old.context {
                try? await webExtensionController.unload(oldContext)
            }
        }

        guard let newItem = await loadExtension(from: targetDir, id: extensionId) else {
            throw CRXExtractorError.manifestNotFound
        }

        if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
            installedExtensions[index] = newItem
        } else {
            installedExtensions.append(newItem)
        }
    }

    func installFromLocalDirectory(url: URL) async throws {
        isInstalling = true
        installStatusMessage = "Instalando extensão da pasta..."
        defer {
            isInstalling = false
            installStatusMessage = nil
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CRXExtractorError.manifestNotFound
        }

        let id = url.lastPathComponent
        let targetDir = extensionsDirectory.appendingPathComponent(id)

        if FileManager.default.fileExists(atPath: targetDir.path) {
            try? FileManager.default.removeItem(at: targetDir)
        }
        try FileManager.default.copyItem(at: url, to: targetDir)

        guard let newItem = await loadExtension(from: targetDir, id: id) else {
            throw CRXExtractorError.manifestNotFound
        }

        if let index = installedExtensions.firstIndex(where: { $0.id == id }) {
            installedExtensions[index] = newItem
        } else {
            installedExtensions.append(newItem)
        }
    }

    // MARK: - State Management

    func toggleExtension(_ item: ExtensionItem) {
        guard let index = installedExtensions.firstIndex(where: { $0.id == item.id }) else { return }

        let willBeEnabled = !item.isEnabled
        var updated = item
        updated.isEnabled = willBeEnabled
        installedExtensions[index] = updated

        var currentDisabled = disabledIds
        if willBeEnabled {
            currentDisabled.remove(item.id)
            disabledIds = currentDisabled
            if let context = item.context {
                Task {
                    try? await webExtensionController.load(context)
                }
            }
        } else {
            currentDisabled.insert(item.id)
            disabledIds = currentDisabled
            if let context = item.context {
                Task {
                    try? await webExtensionController.unload(context)
                }
            }
        }
    }

    func uninstallExtension(_ item: ExtensionItem) {
        if let context = item.context {
            Task {
                try? await webExtensionController.unload(context)
            }
        }

        try? FileManager.default.removeItem(at: item.directoryURL)
        installedExtensions.removeAll { $0.id == item.id }

        var currentDisabled = disabledIds
        currentDisabled.remove(item.id)
        disabledIds = currentDisabled
    }

    func action(for item: ExtensionItem, in tab: (any WKWebExtensionTab)? = nil) -> WKWebExtension.Action? {
        guard let context = item.context else { return nil }
        return context.action(for: tab)
    }
}

// MARK: - WKWebExtensionControllerDelegate

extension ExtensionManager: WKWebExtensionControllerDelegate {
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: WKWebExtensionTab?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        // Automatically grant requested permissions for seamless user experience
        completionHandler(permissions, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: WKWebExtensionTab?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        // Automatically grant requested host match patterns
        completionHandler(matchPatterns, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: WKWebExtensionTab?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        completionHandler(urls, nil)
    }
}
