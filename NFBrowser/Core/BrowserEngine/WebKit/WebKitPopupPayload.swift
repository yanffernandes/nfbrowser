import Foundation
@preconcurrency import WebKit

/// WebKit builds the popup's web view from `configuration`, which keeps `window.opener` working.
struct WebKitPopupPayload: BrowserPopupEnginePayload {
    let configuration: WKWebViewConfiguration
    var navigationAction: WKNavigationAction?
    var windowFeatures: WKWindowFeatures?
}
