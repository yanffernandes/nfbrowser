import AppKit

/// Camera, microphone and screen requests from one tab's pages. The user is asked once
/// per site, and the answer holds until the tab loads another page.
final class MediaCapturePermissions {
    /// Asks the user whether `site` may use `devices`; call `answer` exactly once.
    typealias Ask = (_ site: String, _ devices: BrowserMediaDevices, _ answer: @escaping (Bool) -> Void) -> Void

    private final class Question {
        let devices: BrowserMediaDevices
        var requests: [(devices: BrowserMediaDevices, decision: (Bool) -> Void)]

        init(devices: BrowserMediaDevices, decision: @escaping (Bool) -> Void) {
            self.devices = devices
            requests = [(devices, decision)]
        }
    }

    private let ask: Ask
    private var allowed: [String: BrowserMediaDevices] = [:]
    private var denied: [String: BrowserMediaDevices] = [:]
    private var questions: [String: Question] = [:]

    init(ask: @escaping Ask) {
        self.ask = ask
    }

    func request(_ devices: BrowserMediaDevices, from site: String, decision: @escaping (Bool) -> Void) {
        if allowed[site, default: []].isSuperset(of: devices) {
            decision(true)
        } else if !denied[site, default: []].isDisjoint(with: devices) {
            decision(false)
        } else if let question = questions[site] {
            // Pages often ask again before the user has answered.
            question.requests.append((devices, decision))
        } else {
            let question = Question(devices: devices, decision: decision)
            questions[site] = question
            ask(site, devices) { [weak self] granted in
                guard let self else {
                    question.requests.forEach { $0.decision(false) }
                    return
                }
                answer(question, from: site, granted: granted)
            }
        }
    }

    /// The tab loaded another page.
    func reset() {
        allowed = [:]
        denied = [:]
        questions = [:]
    }

    /// "Allow “meet.google.com” to use your camera and microphone?"
    static func question(for devices: BrowserMediaDevices, from site: String) -> String {
        let inputs = [(BrowserMediaDevices.camera, "camera"), (.microphone, "microphone")]
            .filter { devices.contains($0.0) }
            .map(\.1)
        var uses: [String] = []
        if !inputs.isEmpty {
            uses.append("use your " + inputs.joined(separator: " and "))
        }
        if devices.contains(.screen) {
            uses.append("share your screen")
        }
        return "Allow “\(site)” to \(uses.joined(separator: " and "))?"
    }

    /// The site as people know it: the host, and the port if it isn't the default one.
    static func siteName(for origin: URL?) -> String {
        guard let origin, let host = origin.host(), !host.isEmpty else {
            return origin?.absoluteString ?? "This page"
        }
        return origin.port.map { "\(host):\($0)" } ?? host
    }

    /// A sheet on `window`, or on the visible window when the page isn't in one, as with
    /// a tab in the background. Return doesn't answer it: a key press meant for the page
    /// could otherwise allow the request.
    static func askInSheet(
        _ devices: BrowserMediaDevices,
        from site: String,
        near window: NSWindow?,
        answer: @escaping (Bool) -> Void
    ) {
        let window = [window, NSApp.keyWindow].compactMap { $0 }.first(where: \.isVisible)
            ?? NSApp.windows.first(where: \.isVisible)
        guard let window else {
            answer(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = question(for: devices, from: site)
        if !devices.contains(.screen) {
            alert.informativeText = "Your answer applies until you reload or leave the page."
        }
        alert.addButton(withTitle: "Allow").keyEquivalent = ""
        alert.addButton(withTitle: "Don't Allow").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            answer(response == .alertFirstButtonReturn)
        }
    }

    private func answer(_ question: Question, from site: String, granted: Bool) {
        guard questions[site] === question else {
            // The page that asked is gone.
            question.requests.forEach { $0.decision(false) }
            return
        }
        questions[site] = nil
        if granted {
            // Like other browsers, ask again each time a page wants to share the screen.
            allowed[site, default: []].formUnion(question.devices.subtracting(.screen))
        } else {
            denied[site, default: []].formUnion(question.devices)
        }
        for request in question.requests {
            if question.devices.isSuperset(of: request.devices) {
                request.decision(granted)
            } else {
                self.request(request.devices, from: site, decision: request.decision)
            }
        }
    }
}
