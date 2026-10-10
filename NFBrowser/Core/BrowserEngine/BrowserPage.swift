import AppKit
import Foundation

/// Engine-neutral surface of a page; the app talks to WebKit and Chromium tabs only through this.
protocol BrowserPage: AnyObject {
    var engineKind: BrowserEngineKind { get }
    var delegate: BrowserPageDelegate? { get set }
    var contentView: NSView { get }
    var window: NSWindow? { get }
    var currentURL: URL? { get }
    var title: String? { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    var isLoading: Bool { get }
    var estimatedProgress: Double { get }
    var lastCommittedURL: URL? { get }
    var isDownloadNavigation: Bool { get }

    func load(_ request: URLRequest)
    func reload()
    func goBack()
    func goForward()
    func stopLoading()
    func evaluateJavaScript(_ script: String, completion: ((Any?, Error?) -> Void)?)
    func takeSnapshot(configuration: BrowserSnapshotConfiguration, completion: @escaping (NSImage?, Error?) -> Void)
    func closeMediaPresentations(completion: @escaping () -> Void)
    func teardown()
    func bypassSSL(for host: String)
}

extension BrowserPage {
    func evaluateJavaScript(_ script: String) {
        evaluateJavaScript(script, completion: nil)
    }
}
