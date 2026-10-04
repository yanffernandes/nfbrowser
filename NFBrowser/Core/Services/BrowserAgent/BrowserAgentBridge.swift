import AppKit
import Foundation
import Network

struct BrowserAgentHTTPResponse {
    let status: Int
    let body: [String: Any]

    static func success(_ body: [String: Any] = [:]) -> Self {
        Self(status: 200, body: ["ok": true].merging(body) { _, new in new })
    }

    static func failure(_ message: String, status: Int = 400) -> Self {
        Self(status: status, body: ["ok": false, "error": message])
    }
}

@MainActor
final class BrowserAgentBridge: ObservableObject {
    @Published private(set) var endpoint: String?
    @Published private(set) var isRunning = false

    private weak var tabManager: TabManager?
    private var listener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.orabrowser.agent-browser-bridge")
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var sessionToken: String?
    private var references: [String: ReferenceContext] = [:]

    private struct ReferenceContext {
        let tabID: UUID
        let url: String
        let generation: String
        let requiresConfirmation: Bool
    }

    func attach(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func start() async throws {
        if isRunning {
            return
        }
        guard listener == nil else { throw BridgeError.alreadyStarting }

        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        sessionToken = token
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            sessionToken = nil
            throw error
        }
        self.listener = listener
        let queue = networkQueue

        try await withCheckedThrowingContinuation { continuation in
            readyContinuation = continuation
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self else { return }
                    guard self.listener === listener, self.sessionToken != nil else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port?.rawValue else {
                            self.readyContinuation?.resume(throwing: BridgeError.listenerPortUnavailable)
                            self.readyContinuation = nil
                            return
                        }
                        self.endpoint = "http://127.0.0.1:\(port)"
                        self.isRunning = true
                        self.readyContinuation?.resume()
                        self.readyContinuation = nil
                    case let .failed(error):
                        self.readyContinuation?.resume(throwing: error)
                        self.readyContinuation = nil
                        self.listener = nil
                        self.sessionToken = nil
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: queue)
                Task { @MainActor [weak self] in
                    self?.receive(connection, accumulated: Data())
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        endpoint = nil
        sessionToken = nil
        isRunning = false
        references.removeAll()
        readyContinuation?.resume(throwing: BridgeError.stopped)
        readyContinuation = nil
    }

    func environmentValues() -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        values["ORA_BROWSER_ENDPOINT"] = endpoint
        values["ORA_BROWSER_TOKEN"] = sessionToken
        return values
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                var received = accumulated
                if let data {
                    received.append(data)
                }

                switch Self.parseRequest(received) {
                case .incomplete:
                    if isComplete || error != nil || received.count > 1_100_000 {
                        self.respond(.failure("Incomplete or oversized request", status: 413), on: connection)
                    } else {
                        self.receive(connection, accumulated: received)
                    }
                case let .invalid(message, status):
                    self.respond(.failure(message, status: status), on: connection)
                case let .request(request):
                    guard self.authorized(request.headers["authorization"]) else {
                        self.respond(.failure("Unauthorized", status: 401), on: connection)
                        return
                    }
                    guard request.method == "POST", request.path.hasPrefix("/browser/") else {
                        self.respond(.failure("Not found", status: 404), on: connection)
                        return
                    }
                    Task { @MainActor in
                        let response = await self.handle(
                            action: String(request.path.dropFirst("/browser/".count)),
                            payload: request.payload
                        )
                        self.respond(response, on: connection)
                    }
                }
            }
        }
    }

    private func authorized(_ header: String?) -> Bool {
        guard let token = sessionToken,
              let header,
              header.hasPrefix("Bearer ")
        else { return false }
        let supplied = String(header.dropFirst("Bearer ".count))
        guard supplied.utf8.count == token.utf8.count else { return false }
        return zip(supplied.utf8, token.utf8).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private func respond(_ response: BrowserAgentHTTPResponse, on connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: response.body, options: [.sortedKeys])) ??
            Data("{}".utf8)
        let reason = switch response.status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        default: "Error"
        }
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\n".utf8)
        data.append(Data("Content-Type: application/json; charset=utf-8\r\n".utf8))
        data.append(Data("Content-Length: \(body.count)\r\n".utf8))
        data.append(Data("Cache-Control: no-store\r\nConnection: close\r\n\r\n".utf8))
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func handle(action: String, payload: [String: Any]) async -> BrowserAgentHTTPResponse {
        guard let tabManager else {
            return .failure("NF Browser is not ready", status: 500)
        }

        switch action {
        case "tabs": return tabsResponse(from: tabManager)
        case "switch": return switchTab(payload, in: tabManager)
        case "open", "new-tab": return openNewTab(payload, in: tabManager)
        case "close-tab": return closeTabAction(payload, in: tabManager)
        case "search": return searchAction(payload, in: tabManager)
        case "navigate": return navigate(payload, in: tabManager)
        case "snapshot":
            return await snapshot(tabManager.activeTab)
        case "screenshot":
            return await screenshot(tabManager.activeTab)
        case "text":
            return await extractText(tabManager.activeTab)
        case "back": return navigateBack(in: tabManager)
        case "forward": return navigateForward(in: tabManager)
        case "reload": return reload(in: tabManager)
        case "scroll": return await scroll(payload, in: tabManager)
        case "click": return await click(tabManager.activeTab, payload: payload)
        case "fill": return await fill(tabManager.activeTab, payload: payload)
        default:
            return .failure("Unknown browser command", status: 404)
        }
    }

    private func tabsResponse(from tabManager: TabManager) -> BrowserAgentHTTPResponse {
        let tabs = (tabManager.activeContainer?.tabs ?? [])
            .sorted { $0.order > $1.order }
            .map { tab in
                [
                    "id": tab.id.uuidString,
                    "title": tab.title,
                    "url": tab.currentPageURL?.absoluteString ?? tab.url.absoluteString,
                    "active": tabManager.activeTab?.id == tab.id
                ] as [String: Any]
            }
        return .success(["tabs": tabs, "space": tabManager.activeContainer?.name ?? ""])
    }

    private func switchTab(_ payload: [String: Any], in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let rawID = payload["tab_id"] as? String, let id = UUID(uuidString: rawID),
              let container = tabManager.activeContainer,
              let tab = container.tabs.first(where: { $0.id == id })
        else { return .failure("Tab not found in the active Space") }
        tabManager.activateTab(tab)
        tab.markAgentActive(status: "Switched to tab", duration: 2.0)
        references.removeAll()
        return .success(["active_tab": id.uuidString, "url": tab.url.absoluteString])
    }

    private func openNewTab(_ payload: [String: Any], in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let rawURL = payload["url"] as? String,
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil
        else {
            return .failure("Valid HTTP or HTTPS URL is required")
        }
        let focus = payload["focus"] as? Bool ?? true
        let historyManager = tabManager.activeTab?.historyManager ?? HistoryManager(
            modelContainer: tabManager.modelContainer,
            modelContext: tabManager.modelContext
        )
        guard let newTab = tabManager.openTab(
            url: url,
            historyManager: historyManager,
            downloadManager: tabManager.activeTab?.downloadManager,
            focusAfterOpening: focus,
            isPrivate: tabManager.activeTab?.isPrivate ?? false
        ) else {
            return .failure("Could not create tab", status: 500)
        }
        newTab.markAgentActive(status: "Opened new tab", duration: 2.5)
        return .success([
            "tab_id": newTab.id.uuidString,
            "url": newTab.url.absoluteString,
            "title": newTab.title,
            "focused": focus
        ])
    }

    private func closeTabAction(_ payload: [String: Any], in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        let tab: Tab?
        if let rawID = payload["tab_id"] as? String, let id = UUID(uuidString: rawID) {
            tab = tabManager.activeContainer?.tabs.first(where: { $0.id == id })
        } else {
            tab = tabManager.activeTab
        }
        guard let targetTab = tab else { return .failure("Tab not found") }
        let idString = targetTab.id.uuidString
        tabManager.closeTab(tab: targetTab)
        return .success(["closed_tab": idString])
    }

    private func searchAction(_ payload: [String: Any], in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let query = (payload["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return .failure("Search query is required")
        }
        let openInNewTab = payload["new_tab"] as? Bool ?? true
        let searchService = SearchEngineService()
        let containerId = tabManager.activeContainer?.id
        let searchURL: URL
        if let engine = searchService.getDefaultSearchEngine(for: containerId),
           let url = searchService.createSearchURL(for: engine, query: query) {
            searchURL = url
        } else if let fallback = URL(string: "https://www.google.com/search?q=" + (query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
            searchURL = fallback
        } else {
            return .failure("Could not create search URL", status: 500)
        }

        if openInNewTab {
            let historyManager = tabManager.activeTab?.historyManager ?? HistoryManager(
                modelContainer: tabManager.modelContainer,
                modelContext: tabManager.modelContext
            )
            guard let newTab = tabManager.openTab(
                url: searchURL,
                historyManager: historyManager,
                downloadManager: tabManager.activeTab?.downloadManager,
                focusAfterOpening: true,
                isPrivate: tabManager.activeTab?.isPrivate ?? false
            ) else {
                return .failure("Could not open search tab", status: 500)
            }
            newTab.markAgentActive(status: "Searching \"\(query)\"...", duration: 3.0)
            return .success([
                "tab_id": newTab.id.uuidString,
                "query": query,
                "url": searchURL.absoluteString
            ])
        } else {
            guard let activeTab = tabManager.activeTab else { return .failure("No active tab") }
            activeTab.loadURL(searchURL.absoluteString)
            activeTab.markAgentActive(status: "Searching \"\(query)\"...", duration: 3.0)
            return .success([
                "tab_id": activeTab.id.uuidString,
                "query": query,
                "url": searchURL.absoluteString
            ])
        }
    }

    private func extractText(_ tab: Tab?) async -> BrowserAgentHTTPResponse {
        guard let tab, tab.isWebViewReady else { return .failure("No active page") }
        tab.markAgentActive(status: "Reading page text...", duration: 2.0)
        let script = """
        (() => {
          const article = document.querySelector('article, [role="article"], main, [role="main"], .post-content, #content');
          const root = article || document.body;
          const text = root ? (root.innerText || "").trim() : "";
          return JSON.stringify({
            title: document.title,
            url: location.href,
            text: text.slice(0, 80000)
          });
        })()
        """
        do {
            let result = try await evaluate(tab, script: script)
            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .failure("Could not extract page text", status: 500) }
            return .success(parsed)
        } catch {
            return .failure("Could not extract page text: \(error.localizedDescription)", status: 500)
        }
    }

    private func navigate(_ payload: [String: Any], in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let tab = tabManager.activeTab else { return .failure("No active tab") }
        guard let rawURL = payload["url"] as? String,
              let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              url.user == nil,
              url.password == nil
        else { return .failure("Only absolute HTTP and HTTPS URLs are allowed") }
        tab.loadURL(url.absoluteString)
        tab.markAgentActive(status: "Navigating to \(url.host ?? "page")...", duration: 3.0)
        references = references.filter { $0.value.tabID != tab.id }
        return .success(["navigating_to": url.absoluteString])
    }

    private func navigateBack(in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let tab = tabManager.activeTab, tab.canGoBack else { return .failure("No previous page") }
        tab.goBack()
        tab.markAgentActive(status: "Navigating back...", duration: 2.0)
        references = references.filter { $0.value.tabID != tab.id }
        return .success(["action": "back"])
    }

    private func navigateForward(in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let tab = tabManager.activeTab, tab.canGoForward else { return .failure("No next page") }
        tab.goForward()
        tab.markAgentActive(status: "Navigating forward...", duration: 2.0)
        references = references.filter { $0.value.tabID != tab.id }
        return .success(["action": "forward"])
    }

    private func reload(in tabManager: TabManager) -> BrowserAgentHTTPResponse {
        guard let tab = tabManager.activeTab else { return .failure("No active tab") }
        tab.reload()
        tab.markAgentActive(status: "Reloading page...", duration: 2.0)
        references = references.filter { $0.value.tabID != tab.id }
        return .success(["action": "reload"])
    }

    private func scroll(_ payload: [String: Any], in tabManager: TabManager) async -> BrowserAgentHTTPResponse {
        guard let tab = tabManager.activeTab, tab.isWebViewReady else { return .failure("No active page") }
        let direction = payload["direction"] as? String ?? "down"
        let pixels = min(max(abs(payload["pixels"] as? Int ?? 600), 1), 3000)
        let scrollLeft = direction == "left" ? -pixels : direction == "right" ? pixels : 0
        let scrollTop = direction == "up" ? -pixels : direction == "down" ? pixels : 0
        guard ["up", "down", "left", "right"].contains(direction) else {
            return .failure("Direction must be up, down, left, or right")
        }
        tab.markAgentActive(status: "Scrolling \(direction)...", duration: 1.5)
        let script = "window.scrollBy({left: \(scrollLeft), top: \(scrollTop), behavior: 'smooth'}); true"
        _ = try? await evaluate(tab, script: script)
        return .success(["scrolled": direction, "pixels": pixels])
    }

    private func snapshot(_ tab: Tab?) async -> BrowserAgentHTTPResponse {
        guard let tab, tab.isWebViewReady else { return .failure("No active page") }
        tab.markAgentActive(status: "Reading page elements...", duration: 2.0)
        let generation = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        guard let generationLiteral = Self.javascriptLiteral(generation) else {
            return .failure("Could not prepare page snapshot", status: 500)
        }
        let property = "__oraBrowserAgent_\(generation)"
        let script = """
        (() => {
          const generation = \(generationLiteral);
          const property = "\(property)";
          const isVisible = (element) => {
            const style = window.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            return style.display !== "none" && style.visibility !== "hidden" && Number(style.opacity) > 0 && rect.width > 0 && rect.height > 0;
          };
          const candidates = Array.from(document.querySelectorAll(
            'a[href],button,input:not([type="hidden"]),textarea,select,[role="button"],[role="link"],[tabindex]:not([tabindex="-1"])'
          )).filter(isVisible).slice(0, 120);
          const refs = Object.create(null);
          const elements = candidates.map((element, index) => {
            const reference = `@e${index + 1}`;
            refs[reference] = element;
            const tag = element.tagName.toLowerCase();
            const type = (element.getAttribute("type") || "").toLowerCase();
            const text = (element.innerText || element.getAttribute("aria-label") || element.getAttribute("title") || element.getAttribute("placeholder") || "").trim().replace(/\\s+/g, " ").slice(0, 240);
            const label = element.getAttribute("aria-label") || element.getAttribute("title") || text;
            const href = tag === "a" ? element.href : null;
            return {
              reference,
              tag,
              type,
              role: element.getAttribute("role") || (tag === "a" ? "link" : tag === "button" ? "button" : "input"),
              label,
              text,
              href,
              disabled: Boolean(element.disabled),
              requires_confirmation: tag !== "a" || !["http:", "https:"].includes(new URL(element.href, location.href).protocol) || type === "submit" || Boolean(element.hasAttribute("download"))
            };
          });
          window[property] = { generation, refs };
          return JSON.stringify({
            generation,
            url: location.href,
            title: document.title,
            text: (document.body?.innerText || "").slice(0, 60000),
            elements
          });
        })()
        """
        do {
            let result = try await evaluate(tab, script: script)
            guard let raw = result as? String,
                  let data = raw.data(using: .utf8),
                  let pageSnapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return .failure("Could not read page snapshot", status: 500) }

            let url = pageSnapshot["url"] as? String ?? tab.currentPageURL?.absoluteString ?? ""
            if let elements = pageSnapshot["elements"] as? [[String: Any]] {
                references = references.filter { $0.value.tabID != tab.id }
                for element in elements {
                    guard let reference = element["reference"] as? String else { continue }
                    references[reference] = ReferenceContext(
                        tabID: tab.id,
                        url: url,
                        generation: generation,
                        requiresConfirmation: element["requires_confirmation"] as? Bool ?? true
                    )
                }
            }
            return .success([
                "active_tab": tab.id.uuidString,
                "space": tab.container.name,
                "snapshot": pageSnapshot
            ])
        } catch {
            return .failure("Could not snapshot page: \(error.localizedDescription)", status: 500)
        }
    }

    private func screenshot(_ tab: Tab?) async -> BrowserAgentHTTPResponse {
        guard let tab, tab.isWebViewReady else { return .failure("No active page") }
        tab.markAgentActive(status: "Capturing viewport screenshot...", duration: 1.5)
        do {
            let image: NSImage = try await withCheckedThrowingContinuation { continuation in
                tab.takeSnapshot(configuration: .full) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: BridgeError.screenshotUnavailable)
                    }
                }
            }
            guard let png = image.pngData() else { return .failure("Could not encode screenshot", status: 500) }
            guard png.count <= 12 * 1024 * 1024 else { return .failure(
                "Screenshot is too large; use the page snapshot instead",
                status: 413
            ) }
            return .success([
                "active_tab": tab.id.uuidString,
                "url": tab.currentPageURL?.absoluteString ?? tab.url.absoluteString,
                "png_base64": png.base64EncodedString()
            ])
        } catch {
            return .failure("Could not take screenshot: \(error.localizedDescription)", status: 500)
        }
    }

    private func click(_ tab: Tab?, payload: [String: Any]) async -> BrowserAgentHTTPResponse {
        guard let tab, tab.isWebViewReady else { return .failure("No active page") }
        guard let reference = payload["reference"] as? String,
              let context = references[reference],
              context.tabID == tab.id,
              context.url == (tab.currentPageURL?.absoluteString ?? tab.url.absoluteString)
        else { return .failure("That reference is stale; run ora-browser snapshot again") }
        let confirmed = payload["confirm"] as? Bool ?? false
        guard !context.requiresConfirmation || confirmed else {
            return .failure(
                "This control may submit a form or change page state. Ask the user, then retry with --confirm"
            )
        }
        guard let referenceLiteral = Self.javascriptLiteral(reference),
              let generationLiteral = Self.javascriptLiteral(context.generation)
        else { return .failure("Invalid element reference") }
        let script = """
        (() => {
          const state = window["__oraBrowserAgent_\(context.generation)"];
          if (!state || state.generation !== \(generationLiteral)) return "stale";
          const element = state.refs[\(referenceLiteral)];
          if (!element || !element.isConnected || element.disabled) return "stale";
          try {
            const rect = element.getBoundingClientRect();
            const ring = document.createElement("div");
            ring.style.position = "fixed";
            ring.style.left = (rect.left - 4) + "px";
            ring.style.top = (rect.top - 4) + "px";
            ring.style.width = (rect.width + 8) + "px";
            ring.style.height = (rect.height + 8) + "px";
            ring.style.borderRadius = "8px";
            ring.style.border = "3px solid #8b5cf6";
            ring.style.boxShadow = "0 0 16px rgba(139, 92, 246, 0.8), inset 0 0 8px rgba(139, 92, 246, 0.4)";
            ring.style.pointerEvents = "none";
            ring.style.zIndex = "2147483647";
            ring.style.transition = "all 0.6s cubic-bezier(0.16, 1, 0.3, 1)";
            ring.style.transform = "scale(0.95)";
            ring.style.opacity = "1";
            document.documentElement.appendChild(ring);
            requestAnimationFrame(() => {
              ring.style.transform = "scale(1.08)";
              ring.style.opacity = "0";
              setTimeout(() => ring.remove(), 600);
            });
          } catch (e) {}
          element.click();
          return "clicked";
        })()
        """
        do {
            let result = try await evaluate(tab, script: script)
            guard result as? String == "clicked"
            else { return .failure("That reference is stale; run ora-browser snapshot again") }
            tab.markAgentActive(status: "Clicked \(reference)", duration: 2.5)
            references = references.filter { $0.value.tabID != tab.id }
            return .success(["clicked": reference])
        } catch {
            return .failure("Could not click element: \(error.localizedDescription)", status: 500)
        }
    }

    private func fill(_ tab: Tab?, payload: [String: Any]) async -> BrowserAgentHTTPResponse {
        guard let tab, tab.isWebViewReady else { return .failure("No active page") }
        guard let reference = payload["reference"] as? String,
              let context = references[reference],
              context.tabID == tab.id,
              context.url == (tab.currentPageURL?.absoluteString ?? tab.url.absoluteString)
        else { return .failure("That reference is stale; run ora-browser snapshot again") }
        guard let text = payload["text"] as? String, text.count <= 20000,
              let referenceLiteral = Self.javascriptLiteral(reference),
              let generationLiteral = Self.javascriptLiteral(context.generation),
              let textLiteral = Self.javascriptLiteral(text)
        else { return .failure("Text is missing or too long") }
        let script = """
        (() => {
          const state = window["__oraBrowserAgent_\(context.generation)"];
          if (!state || state.generation !== \(generationLiteral)) return "stale";
          const element = state.refs[\(referenceLiteral)];
          if (!element || !element.isConnected || element.disabled || element.readOnly) return "stale";
          if (element instanceof HTMLInputElement && ["password", "hidden", "file"].includes(element.type.toLowerCase())) return "sensitive";
          if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement || element instanceof HTMLSelectElement || element.isContentEditable)) return "not-fillable";
          try {
            const rect = element.getBoundingClientRect();
            const ring = document.createElement("div");
            ring.style.position = "fixed";
            ring.style.left = (rect.left - 4) + "px";
            ring.style.top = (rect.top - 4) + "px";
            ring.style.width = (rect.width + 8) + "px";
            ring.style.height = (rect.height + 8) + "px";
            ring.style.borderRadius = "8px";
            ring.style.border = "2px solid #3b82f6";
            ring.style.boxShadow = "0 0 14px rgba(59, 130, 246, 0.8)";
            ring.style.pointerEvents = "none";
            ring.style.zIndex = "2147483647";
            ring.style.transition = "all 0.8s ease-out";
            ring.style.opacity = "1";
            document.documentElement.appendChild(ring);
            setTimeout(() => {
              ring.style.opacity = "0";
              setTimeout(() => ring.remove(), 800);
            }, 400);
          } catch (e) {}
          element.focus();
          if (element.isContentEditable) {
            element.textContent = \(textLiteral);
          } else {
            const prototype = element instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : element instanceof HTMLSelectElement ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
            const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
            if (setter) setter.call(element, \(textLiteral)); else element.value = \(textLiteral);
          }
          element.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: \(textLiteral) }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return "filled";
        })()
        """
        do {
            let result = try await evaluate(tab, script: script) as? String
            switch result {
            case "filled":
                tab.markAgentActive(status: "Filled \(reference)", duration: 2.5)
                return .success(["filled": reference, "submitted": false])
            case "sensitive": return .failure("NF Browser will not fill password, hidden, or file inputs")
            case "not-fillable": return .failure("That element is not a text field")
            default: return .failure("That reference is stale; run ora-browser snapshot again")
            }
        } catch {
            return .failure("Could not fill element: \(error.localizedDescription)", status: 500)
        }
    }

    private func evaluate(_ tab: Tab, script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            tab.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private static func javascriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed]),
              let array = String(data: data, encoding: .utf8),
              array.count >= 2
        else { return nil }
        return String(array.dropFirst().dropLast())
    }

    private static func parseRequest(_ data: Data) -> RequestParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            return data.count > 32768 ? .invalid("Request headers too large", 413) : .incomplete
        }
        let headerData = data[..<range.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Invalid request headers", 400)
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid("Missing request line", 400) }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else { return .invalid("Invalid request line", 400) }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? -1
        guard contentLength >= 0 else { return .invalid("Invalid content length", 400) }
        guard contentLength <= 1_000_000 else { return .invalid("Request body too large", 413) }
        let bodyStart = range.upperBound
        guard data.count >= bodyStart + contentLength else { return .incomplete }
        let bodyData = data[bodyStart ..< (bodyStart + contentLength)]
        let payload: [String: Any]
        if contentLength == 0 {
            payload = [:]
        } else if let object = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            payload = object
        } else {
            return .invalid("Request body must be a JSON object", 400)
        }
        return .request(HTTPRequest(
            method: String(parts[0]),
            path: String(parts[1].split(separator: "?", maxSplits: 1).first ?? ""),
            headers: headers,
            payload: payload
        ))
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let payload: [String: Any]
}

private enum RequestParseResult {
    case incomplete
    case invalid(String, Int)
    case request(HTTPRequest)
}

private enum BridgeError: LocalizedError {
    case alreadyStarting
    case listenerPortUnavailable
    case screenshotUnavailable
    case stopped

    var errorDescription: String? {
        switch self {
        case .alreadyStarting: "The browser-control listener is already starting"
        case .listenerPortUnavailable: "The local browser-control listener did not receive a port"
        case .screenshotUnavailable: "The browser page did not return a screenshot"
        case .stopped: "The browser-control listener was stopped"
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
