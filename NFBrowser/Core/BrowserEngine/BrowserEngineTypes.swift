import AppKit
import Foundation

enum BrowserEngineKind: String, Codable, CaseIterable, Identifiable {
    case webkit = "webkit"
    case chromium = "chromium"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .webkit: return "WebKit"
        case .chromium: return "Chromium"
        }
    }

    var shortDescription: String {
        switch self {
        case .webkit: return "Native macOS Safari engine (fast & lightweight)"
        case .chromium: return "Real Chromium via CEF (no DRM or H.264 video)"
        }
    }

    var iconSystemName: String {
        switch self {
        case .webkit: return "safari"
        case .chromium: return "globe"
        }
    }
}

enum BrowserWebsiteDataType: Hashable {
    case cookies
    case cache
    case all
}

enum BrowserUserScriptInjectionTime {
    case atDocumentStart
    case atDocumentEnd
}

struct BrowserUserScript {
    let name: String?
    let source: String
    let injectionTime: BrowserUserScriptInjectionTime
    let forMainFrameOnly: Bool
}

struct BrowserScriptMessage {
    let name: String
    let body: Any?
}

struct BrowserOpenPanelOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

enum BrowserPermissionKind {
    case mediaCapture
}

enum BrowserPermissionDecision {
    case grant
    case deny
}

struct BrowserNavigationAction {
    let request: URLRequest
    let modifierFlags: NSEvent.ModifierFlags
}

enum BrowserNavigationActionDisposition {
    case allow
    case cancel
    case openInNewTab
}

enum BrowserNavigationPhase {
    case started
    case committed
    case finished
}

struct BrowserNavigationEvent {
    let phase: BrowserNavigationPhase
    let url: URL?
    let title: String?
    let progress: Double
    let isLoading: Bool
}

struct BrowserSnapshotConfiguration {
    let rect: CGRect?
    let afterScreenUpdates: Bool

    static let full = BrowserSnapshotConfiguration(rect: nil, afterScreenUpdates: false)
}
