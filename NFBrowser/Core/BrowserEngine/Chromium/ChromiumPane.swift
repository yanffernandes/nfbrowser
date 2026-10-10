import Foundation

/// A DevTools protocol command a Chromium pane runs before its first page loads.
struct ChromiumDevToolsCommand {
    let method: String
    var params: [String: Any]?
}

extension NFChromiumBrowserView {
    /// A standalone Chromium view (QA panes) that runs `setup` before it loads `url`.
    /// DevTools page commands are answered by the renderer, so the view starts on
    /// about:blank to have one, as ChromiumBrowserPage does.
    static func makePane(
        profileIdentifier: String,
        persistent: Bool,
        url: URL,
        setup: [ChromiumDevToolsCommand]
    ) -> NFChromiumBrowserView {
        let view = NFChromiumBrowserView(
            frame: .zero,
            profileIdentifier: profileIdentifier,
            persistent: persistent,
            initialURL: URL(string: "about:blank")
        )
        var didLoad = false
        let loadOnce = { [weak view] in
            guard !didLoad else { return }
            didLoad = true
            view?.load(url)
        }
        let pending = DispatchGroup()
        for command in setup {
            pending.enter()
            view.sendDevToolsMethod(command.method, params: command.params) { _, _ in
                pending.leave()
            }
        }
        pending.notify(queue: .main, execute: loadOnce)
        // Never hold the page hostage to its setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: loadOnce)
        return view
    }
}
