import Foundation
@preconcurrency import WebKit

struct BrowserPageConfiguration {
    let userAgent: String?
    let allowsPictureInPicture: Bool
    let allowsJavaScript: Bool
    let allowsJavaScriptWindowsAutomatically: Bool
    let allowsAirPlayForMediaPlayback: Bool
    let allowsInspectableDebugging: Bool
    let allowsBackForwardNavigationGestures: Bool
    let mediaPlaybackRequiresUserAction: Bool
    let scriptMessageNames: [String]
    let userScripts: [BrowserUserScript]
    let privacySettings: SpacePrivacySettings

    static func oraDefault(
        engineKind: BrowserEngineKind = .webkit,
        userScripts: [BrowserUserScript],
        privacySettings: SpacePrivacySettings
    ) -> BrowserPageConfiguration {
        let ua: String = switch engineKind {
        case .webkit:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        case .chromium:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        }

        return BrowserPageConfiguration(
            userAgent: ua,
            allowsPictureInPicture: true,
            allowsJavaScript: true,
            allowsJavaScriptWindowsAutomatically: true,
            allowsAirPlayForMediaPlayback: true,
            allowsInspectableDebugging: true,
            allowsBackForwardNavigationGestures: true,
            mediaPlaybackRequiresUserAction: false,
            scriptMessageNames: ["listener", "linkHover", "mediaEvent", "passwordManager"],
            userScripts: userScripts,
            privacySettings: privacySettings
        )
    }
}

final class BrowserEngine {
    private struct ProfileKey: Hashable {
        let engineKind: BrowserEngineKind
        let identifier: UUID
        let isPrivate: Bool
    }

    static let shared = BrowserEngine()
    private let profileCacheLock = NSLock()
    private var profileCache: [ProfileKey: BrowserEngineProfile] = [:]

    func makeProfile(
        engineKind: BrowserEngineKind = .webkit,
        identifier: UUID,
        isPrivate: Bool
    ) -> BrowserEngineProfile {
        if isPrivate {
            return BrowserEngineProfile(engineKind: engineKind, identifier: identifier, isPrivate: true)
        }

        let key = ProfileKey(engineKind: engineKind, identifier: identifier, isPrivate: false)
        profileCacheLock.lock()
        defer { profileCacheLock.unlock() }

        if let profile = profileCache[key] {
            return profile
        }

        let profile = BrowserEngineProfile(engineKind: engineKind, identifier: identifier, isPrivate: false)
        profileCache[key] = profile
        return profile
    }

    func makePage(
        engineKind: BrowserEngineKind = .webkit,
        profile: BrowserEngineProfile,
        configuration: BrowserPageConfiguration,
        popupRequest: BrowserPopupRequest? = nil,
        delegate: BrowserPageDelegate?
    ) -> BrowserPage {
        // Chromium Spaces still run on WebKit until the CEF-backed page lands.
        WebKitBrowserPage(
            engineKind: engineKind,
            profile: profile,
            configuration: configuration,
            customConfiguration: (popupRequest?.enginePayload as? WebKitPopupPayload)?.configuration,
            delegate: delegate
        )
    }
}
