import Foundation
import WebKit

final class DeviceSyncBridge: NSObject, WKScriptMessageHandler {
    static let shared = DeviceSyncBridge()
    static let messageName = "qaSyncEvent"

    private struct PeerRegistration {
        let id: UUID
        weak var webView: WKWebView?
    }

    private var peers: [PeerRegistration] = []
    private var isDispatching = false

    override private init() {
        super.init()
    }

    static let injectionScript = """
    (function() {
        if (window.__nfSyncBridgeInstalled) return;
        window.__nfSyncBridgeInstalled = true;
        let isReceivingSync = false;

        function getPathTo(element) {
            if (!element || element === document.body) return 'body';
            if (element.id) return '#' + CSS.escape(element.id);
            if (!element.parentNode) return element.tagName.toLowerCase();
            let ix = 0;
            const siblings = element.parentNode.children || [];
            for (let i = 0; i < siblings.length; i++) {
                const sibling = siblings[i];
                if (sibling === element) {
                    return getPathTo(element.parentNode) + ' > ' + element.tagName.toLowerCase() + ':nth-of-type(' + (ix + 1) + ')';
                }
                if (sibling.tagName === element.tagName) {
                    ix++;
                }
            }
            return element.tagName.toLowerCase();
        }

        window.__nfSyncScroll = function(percentX, percentY) {
            isReceivingSync = true;
            const maxScrollY = document.documentElement.scrollHeight - window.innerHeight;
            const maxScrollX = document.documentElement.scrollWidth - window.innerWidth;
            window.scrollTo({
                left: maxScrollX > 0 ? percentX * maxScrollX : 0,
                top: maxScrollY > 0 ? percentY * maxScrollY : 0,
                behavior: 'instant'
            });
            setTimeout(() => { isReceivingSync = false; }, 60);
        };

        window.__nfSyncClick = function(selector) {
            if (!selector) return;
            try {
                const el = document.querySelector(selector);
                if (el) {
                    isReceivingSync = true;
                    el.click();
                    setTimeout(() => { isReceivingSync = false; }, 80);
                }
            } catch (e) {}
        };

        window.addEventListener('scroll', function() {
            if (isReceivingSync) return;
            const maxScrollY = document.documentElement.scrollHeight - window.innerHeight;
            const maxScrollX = document.documentElement.scrollWidth - window.innerWidth;
            const percentY = maxScrollY > 0 ? window.scrollY / maxScrollY : 0;
            const percentX = maxScrollX > 0 ? window.scrollX / maxScrollX : 0;

            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.qaSyncEvent) {
                window.webkit.messageHandlers.qaSyncEvent.postMessage({
                    type: 'scroll',
                    percentX: percentX,
                    percentY: percentY
                });
            }
        }, { passive: true });

        document.addEventListener('click', function(e) {
            if (isReceivingSync || !e.isTrusted) return;
            const target = e.target;
            if (!target) return;
            
            const selector = getPathTo(target);

            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.qaSyncEvent) {
                window.webkit.messageHandlers.qaSyncEvent.postMessage({
                    type: 'click',
                    selector: selector
                });
            }
        }, true);
    })();
    """

    func register(id: UUID, webView: WKWebView) {
        peers.removeAll { $0.webView == nil || $0.id == id }
        peers.append(PeerRegistration(id: id, webView: webView))
        webView.evaluateJavaScript(Self.injectionScript, completionHandler: nil)
    }

    func unregister(id: UUID) {
        peers.removeAll { $0.id == id }
    }

    var isEnabled: Bool = true

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard isEnabled,
              message.name == Self.messageName,
              let dict = message.body as? [String: Any],
              let type = dict["type"] as? String,
              !isDispatching
        else {
            return
        }

        isDispatching = true
        defer { isDispatching = false }

        let sourceWebView = message.webView

        for peer in peers {
            guard let peerWebView = peer.webView, peerWebView !== sourceWebView else { continue }

            if type == "scroll",
               let percentX = dict["percentX"] as? Double,
               let percentY = dict["percentY"] as? Double
            {
                peerWebView.evaluateJavaScript("window.__nfSyncScroll(\(percentX), \(percentY))", completionHandler: nil)
            } else if type == "click",
                      let selector = dict["selector"] as? String
            {
                let escaped = selector.replacingOccurrences(of: "\"", with: "\\\"")
                peerWebView.evaluateJavaScript("window.__nfSyncClick(\"\(escaped)\")", completionHandler: nil)
            }
        }
    }
}
