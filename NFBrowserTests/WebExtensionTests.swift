import Foundation
@testable import NFBrowser
import Testing
import WebKit

struct WebExtensionTests {

    @Test func extractExtensionIdFromVariousURLs() {
        // Standard URL
        let url1 = URL(string: "https://chromewebstore.google.com/detail/cookie-editor/hlkenndednhfkekhgcdicdfddnkalmdm")!
        #expect(ChromeWebStoreService.extractExtensionId(from: url1) == "hlkenndednhfkekhgcdicdfddnkalmdm")

        // URL with trailing slash
        let url2 = URL(string: "https://chromewebstore.google.com/detail/cookie-editor/hlkenndednhfkekhgcdicdfddnkalmdm/")!
        #expect(ChromeWebStoreService.extractExtensionId(from: url2) == "hlkenndednhfkekhgcdicdfddnkalmdm")

        // URL with query params & hash
        let url3 = URL(string: "https://chromewebstore.google.com/detail/ublock-origin/cjpalhdlnbpafiamejdnhcphjbkeiagm?hl=pt-BR#overview")!
        #expect(ChromeWebStoreService.extractExtensionId(from: url3) == "cjpalhdlnbpafiamejdnhcphjbkeiagm")

        // Non-webstore URL
        let url4 = URL(string: "https://google.com/search?q=test")!
        #expect(ChromeWebStoreService.extractExtensionId(from: url4) == nil)

        // Webstore URL but not a detail page
        let url5 = URL(string: "https://chromewebstore.google.com/category/extensions")!
        #expect(ChromeWebStoreService.extractExtensionId(from: url5) == nil)
    }

    @Test func crxDownloadURLGeneration() {
        let extId = "hlkenndednhfkekhgcdicdfddnkalmdm"
        let downloadURL = ChromeWebStoreService.crxDownloadURL(for: extId)

        #expect(downloadURL.host == "clients2.google.com")
        #expect(downloadURL.absoluteString.contains("x=id%3D\(extId)"))
    }

    @Test @MainActor func loadUnpackedExtensionIntoWebKit() async throws {
        // Create a temporary mock WebExtension folder
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-extension-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manifestContent = """
        {
            "manifest_version": 3,
            "name": "Test Extension",
            "version": "1.2.3",
            "description": "A test WebExtension for NFBrowser",
            "action": {
                "default_title": "Test Action"
            }
        }
        """

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        try manifestContent.data(using: .utf8)!.write(to: manifestURL)

        // Test loading with WKWebExtension
        let webExt = try await WKWebExtension(resourceBaseURL: tempDir)
        #expect(webExt.displayName == "Test Extension")
        #expect(webExt.displayVersion == "1.2.3")
        #expect(webExt.displayDescription == "A test WebExtension for NFBrowser")

        // Test loading through ExtensionManager
        let manager = ExtensionManager.shared
        let item = await manager.loadExtension(from: tempDir, id: "test-extension-id")
        #expect(item != nil)
        #expect(item?.displayName == "Test Extension")
        #expect(item?.version == "1.2.3")
        #expect(item?.extensionDescription == "A test WebExtension for NFBrowser")
    }

    @Test func liveChromeWebStoreDownloadAndExtraction() async throws {
        // Download a small, popular open-source extension (Cookie-Editor: hlkenndednhfkekhgcdicdfddnkalmdm)
        let extId = "hlkenndednhfkekhgcdicdfddnkalmdm"
        let service = ChromeWebStoreService.shared

        let downloadedData = try await service.downloadCRX(extensionId: extId)
        #expect(!downloadedData.isEmpty)
        #expect(downloadedData.count > 1000)

        // Test CRX extraction
        let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("extracted-cookie-editor-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: extractDir) }

        try CRXExtractor.extract(crxData: downloadedData, to: extractDir)

        let manifestPath = extractDir.appendingPathComponent("manifest.json").path
        #expect(FileManager.default.fileExists(atPath: manifestPath))

        // Verify WebKit can parse the extracted extension
        let webExt = try await WKWebExtension(resourceBaseURL: extractDir)
        #expect(webExt.displayName != nil)
        #expect(webExt.version != nil)
    }

    @Test @MainActor func extensionManagerDisabledIdsPersistence() {
        let manager = ExtensionManager.shared
        let extId = "mock-toggle-extension"

        var ids = manager.disabledIds
        ids.insert(extId)
        manager.disabledIds = ids
        #expect(manager.disabledIds.contains(extId))

        ids.remove(extId)
        manager.disabledIds = ids
        #expect(!manager.disabledIds.contains(extId))
    }
}
