import Foundation
import WebKit

/// A QA pane whose scrolls and clicks are mirrored to the other panes.
protocol DeviceSyncPeer: AnyObject {
    func runSyncScript(_ script: String)
}

extension WKWebView: DeviceSyncPeer {
    func runSyncScript(_ script: String) {
        evaluateJavaScript(script, completionHandler: nil)
    }
}

extension NFChromiumBrowserView: DeviceSyncPeer {
    func runSyncScript(_ script: String) {
        evaluateJavaScript(script, completion: nil)
    }
}

final class DeviceSyncBridge: NSObject, WKScriptMessageHandler {
    static let shared = DeviceSyncBridge()
    static let messageName = "qaSyncEvent"
    static let chromiumBindingName = "__nfQASync"

    private struct PeerRegistration {
        let id: UUID
        weak var peer: DeviceSyncPeer?
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

        // WebKit panes post through a script message handler, Chromium panes through a
        // DevTools binding.
        function post(message) {
            const handlers = window.webkit && window.webkit.messageHandlers;
            if (handlers && handlers.qaSyncEvent) {
                handlers.qaSyncEvent.postMessage(message);
            } else if (typeof window.__nfQASync === 'function') {
                window.__nfQASync(JSON.stringify(message));
            }
        }

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

            post({ type: 'scroll', percentX: percentX, percentY: percentY });
        }, { passive: true });

        document.addEventListener('click', function(e) {
            if (isReceivingSync || !e.isTrusted) return;
            const target = e.target;
            if (!target) return;

            const selector = getPathTo(target);

            post({ type: 'click', selector: selector });
        }, true);
    })();
    """

    var isEnabled: Bool = true

    func register(id: UUID, peer: DeviceSyncPeer) {
        peers.removeAll { $0.peer == nil || $0.id == id }
        peers.append(PeerRegistration(id: id, peer: peer))
        peer.runSyncScript(Self.injectionScript)
    }

    func unregister(id: UUID) {
        peers.removeAll { $0.id == id }
    }

    /// Chromium panes report through a DevTools binding; the script is also registered
    /// for every new document the pane loads.
    func installChromiumBridge(on view: NFChromiumBrowserView) {
        view.sendDevToolsMethod("Page.enable", params: nil, completion: nil)
        view.sendDevToolsMethod("Runtime.enable", params: nil, completion: nil)
        view.sendDevToolsMethod("Runtime.addBinding", params: ["name": Self.chromiumBindingName], completion: nil)
        view.sendDevToolsMethod(
            "Page.addScriptToEvaluateOnNewDocument",
            params: ["source": Self.injectionScript],
            completion: nil
        )
    }

    func handleChromiumEvent(method: String, params: [String: Any], from view: NFChromiumBrowserView) {
        guard method == "Runtime.bindingCalled",
              params["name"] as? String == Self.chromiumBindingName,
              let payload = (params["payload"] as? String)?.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return }
        dispatch(event, from: view)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageName, let event = message.body as? [String: Any] else { return }
        dispatch(event, from: message.webView)
    }

    private func dispatch(_ event: [String: Any], from source: AnyObject?) {
        guard isEnabled, !isDispatching, let type = event["type"] as? String else { return }

        isDispatching = true
        defer { isDispatching = false }

        for registration in peers {
            guard let peer = registration.peer, peer !== source else { continue }

            if type == "scroll",
               let percentX = event["percentX"] as? Double,
               let percentY = event["percentY"] as? Double
            {
                peer.runSyncScript("window.__nfSyncScroll(\(percentX), \(percentY))")
            } else if type == "click", let selector = event["selector"] as? String {
                let escaped = selector
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                peer.runSyncScript("window.__nfSyncClick(\"\(escaped)\")")
            }
        }
    }
}
