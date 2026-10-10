import Foundation
@preconcurrency import WebKit

final class WebKitDownloadTask: BrowserDownloadTask, WKDownloadDelegate {
    private let download: WKDownload

    init(download: WKDownload, originalURL: URL) {
        self.download = download
        super.init(originalURL: originalURL, progress: download.progress)
        self.download.delegate = self
    }

    override func cancel() {
        download.cancel()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        if let onDestinationRequest {
            onDestinationRequest(response, suggestedFilename, completionHandler)
        } else {
            completionHandler(nil)
        }
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        if let url = newRequest.url {
            originalURL = url
            onRedirect?(url)
        }
        decisionHandler(.allow)
    }

    func downloadDidFinish(_ download: WKDownload) {
        onFinish?()
    }

    func download(_ download: WKDownload, didFailWithError error: Error) {
        onFail?(error)
    }
}
