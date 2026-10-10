#if DEBUG
    import Foundation
    import Network

    /// Loopback server for the smoke test's third-party cookie probe: a page on localhost
    /// frames a page on 127.0.0.1, a different site, which posts back whether it could
    /// store a cookie.
    final class ChromiumSmokeServer {
        private let listener: NWListener

        init?() {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            guard let listener = try? NWListener(using: parameters, on: .any) else { return nil }
            self.listener = listener
        }

        /// Known once the listener is ready; until then the port reads as 0.
        var topURL: URL? {
            guard let port = listener.port?.rawValue, port != 0 else { return nil }
            return URL(string: "http://localhost:\(port)/top")
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
                let body = request.hasPrefix("GET /frame") ? Self.framePage : self?.topPage ?? ""
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
                    + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }

        /// navigator.cookieEnabled stays true in a blocked frame, so the frame really stores one.
        private static let framePage = """
        <script>
        document.cookie = 'tp=1; SameSite=None; Secure';
        parent.postMessage(document.cookie.includes('tp=1') ? 'stored' : 'blocked', '*');
        </script>
        """

        private var topPage: String {
            """
            <script>addEventListener('message', event => { window.frameCookies = event.data })</script>
            <iframe src="http://127.0.0.1:\(listener.port?.rawValue ?? 0)/frame"></iframe>
            """
        }
    }
#endif
