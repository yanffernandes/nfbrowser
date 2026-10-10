#if DEBUG
    import Foundation
    import Network

    /// Loopback server for the smoke test's privacy probes. `/top` on localhost frames
    /// `/frame` on 127.0.0.1, a different site, which posts back whether it could store a
    /// cookie; `/ads` loads an ad script and an app script and shows an ad banner.
    final class ChromiumSmokeServer {
        private let listener: NWListener

        init?() {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters, on: .any) else { return nil }
            self.listener = listener
        }

        /// Known once the listener is ready; until then the port reads as 0.
        func url(_ path: String) -> URL? {
            guard let port = listener.port?.rawValue, port != 0 else { return nil }
            return URL(string: "http://localhost:\(port)\(path)")
        }

        func start() {
            listener.newConnectionHandler = { [weak self] connection in
                self?.serve(connection)
            }
            listener.start(queue: .main)
        }

        func stop() {
            listener.cancel()
        }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
                let request = data.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let (type, body) = self?.content(for: path) ?? ("text/html", "")
                let response = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\n"
                    + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }

        private func content(for path: String) -> (type: String, body: String) {
            switch path {
            case "/frame":
                ("text/html", Self.framePage)
            case "/ads":
                ("text/html", Self.adsPage)
            case "/ad.js":
                ("text/javascript", "window.loads.push('ad');")
            case "/app.js":
                ("text/javascript", "window.loads.push('app');")
            default:
                ("text/html", topPage)
            }
        }

        /// navigator.cookieEnabled stays true in a blocked frame, so the frame really stores one.
        private static let framePage = """
        <script>
        document.cookie = 'tp=1; SameSite=None; Secure';
        parent.postMessage(document.cookie.includes('tp=1') ? 'stored' : 'blocked', '*');
        </script>
        """

        private static let adsPage = """
        <div class="ad-banner">ad</div>
        <script>window.loads = [];</script>
        <script src="/ad.js"></script>
        <script src="/app.js"></script>
        """

        private var topPage: String {
            """
            <script>addEventListener('message', event => { window.frameCookies = event.data })</script>
            <iframe src="http://127.0.0.1:\(listener.port?.rawValue ?? 0)/frame"></iframe>
            """
        }
    }
#endif
