import Foundation

/// A download handed over by a page; each engine subclasses it and reports through the callbacks.
class BrowserDownloadTask: NSObject {
    let id = UUID()
    var originalURL: URL
    let progress: Progress
    var onDestinationRequest: ((URLResponse, String, @escaping (URL?) -> Void) -> Void)?
    var onRedirect: ((URL) -> Void)?
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    init(originalURL: URL, progress: Progress) {
        self.originalURL = originalURL
        self.progress = progress
        super.init()
    }

    /// Subclasses stop the underlying engine transfer.
    func cancel() {}
}
