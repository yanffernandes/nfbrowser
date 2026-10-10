import Foundation

/// Adapts the app's user scripts, written for WebKit, to Chromium document-start scripts.
enum ChromiumUserScripts {
    /// Takes the DevTools binding off `window` and installs `window.__oraBridge` on top of
    /// it, so app scripts can post messages while pages see neither the binding nor a
    /// `window.webkit` object (which sites read as an embedded-webview signal).
    static func bridgeScript(bindingName: String) -> String {
        """
        (function () {
            const bindingName = '\(bindingName)';
            let send = null;
            const resolveSend = function () {
                if (!send && typeof window[bindingName] === 'function') {
                    send = window[bindingName];
                    try {
                        delete window[bindingName];
                    } catch (error) {}
                }
                return send;
            };
            resolveSend();
            const bridge = {
                postMessage: function (name, payload) {
                    const post = resolveSend();
                    if (!post) {
                        return false;
                    }
                    try {
                        post(JSON.stringify({ name: String(name), body: payload === undefined ? null : payload }));
                        return true;
                    } catch (error) {
                        return false;
                    }
                }
            };
            Object.defineProperty(window, '__oraBridge', {
                value: bridge,
                enumerable: false,
                configurable: false,
                writable: false
            });
        })();
        """
    }

    /// Chromium runs every new-document script at document start in all frames, so the
    /// injection time and frame scope WebKit applied natively are added to the source.
    static func chromiumSource(for script: BrowserUserScript) -> String {
        var source = script.source
        if script.injectionTime == .atDocumentEnd {
            source = """
            (function () {
                const run = function () {
            \(source)
                };
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', run, { once: true });
                } else {
                    run();
                }
            })();
            """
        }
        if script.forMainFrameOnly {
            source = "if (window.top === window) {\n\(source)\n}"
        }
        return source
    }

    /// Decodes a `Runtime.bindingCalled` payload produced by `bridgeScript`.
    static func message(fromBindingPayload payload: String) -> BrowserScriptMessage? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String
        else {
            return nil
        }
        let body = object["body"]
        return BrowserScriptMessage(name: name, body: body is NSNull ? nil : body)
    }
}
