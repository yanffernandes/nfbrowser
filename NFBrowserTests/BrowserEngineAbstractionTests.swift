import Foundation
@testable import NFBrowser
import Testing
@preconcurrency import WebKit

struct BrowserEngineAbstractionTests {
    @Test func profilesAreCachedPerEngineKind() {
        let spaceID = UUID()
        let engine = BrowserEngine.shared

        let webkit = engine.makeProfile(engineKind: .webkit, identifier: spaceID, isPrivate: false)
        let chromium = engine.makeProfile(engineKind: .chromium, identifier: spaceID, isPrivate: false)

        #expect(webkit.engineKind == .webkit)
        #expect(chromium.engineKind == .chromium)
        #expect(webkit !== chromium)
        #expect(engine.makeProfile(engineKind: .chromium, identifier: spaceID, isPrivate: false) === chromium)
    }

    @Test func chromiumProfileClearDataCompletesWithoutWebKit() async {
        let profile = BrowserEngineProfile(engineKind: .chromium, identifier: UUID(), isPrivate: false)

        await withCheckedContinuation { continuation in
            profile.clearData(ofTypes: [.all]) {
                continuation.resume()
            }
        }
    }

    @Test @MainActor func popupRequestCarriesWebKitPayload() {
        let configuration = WKWebViewConfiguration()
        let request = BrowserPopupRequest(
            url: URL(string: "https://example.com/popup"),
            modifierFlags: [.command],
            enginePayload: WebKitPopupPayload(configuration: configuration)
        )

        let payload = request.enginePayload as? WebKitPopupPayload
        #expect(payload?.configuration === configuration)
        #expect(request.modifierFlags.contains(.command))
    }

    @Test @MainActor func makePageReportsRequestedEngineKind() {
        let engine = BrowserEngine.shared
        let configuration = BrowserPageConfiguration.oraDefault(userScripts: [], privacySettings: .init())

        let webkitPage = engine.makePage(
            engineKind: .webkit,
            profile: engine.makeProfile(identifier: UUID(), isPrivate: true),
            configuration: configuration,
            delegate: nil
        )

        #expect(webkitPage.engineKind == .webkit)
        #expect(webkitPage is WebKitBrowserPage)
    }

    @Test func downloadTaskBaseKeepsProgressAndURL() {
        let progress = Progress(totalUnitCount: 10)
        let url = URL(fileURLWithPath: "/tmp/file.zip")
        let task = BrowserDownloadTask(originalURL: url, progress: progress)

        #expect(task.progress === progress)
        #expect(task.originalURL == url)
        task.cancel()
    }
}
