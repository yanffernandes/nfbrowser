import Foundation

/// A Chromium download reported to the app's DownloadManager through BrowserDownloadTask.
final class ChromiumDownloadTask: BrowserDownloadTask {
    private let download: NFChromiumDownload
    private var isSettled = false

    init(download: NFChromiumDownload) {
        self.download = download
        let fallbackURL = URL(string: "about:blank") ?? URL(fileURLWithPath: "/")
        super.init(
            originalURL: download.url ?? download.originalURL ?? fallbackURL,
            progress: Progress(totalUnitCount: max(download.totalBytes, 0))
        )
    }

    override func cancel() {
        download.cancel()
    }

    func update(from download: NFChromiumDownload) {
        if download.totalBytes > 0 {
            progress.totalUnitCount = download.totalBytes
        }
        progress.completedUnitCount = download.receivedBytes

        guard !isSettled else { return }
        if download.isComplete {
            isSettled = true
            onFinish?()
        } else if download.isCanceled || download.isInterrupted {
            isSettled = true
            let reason = download.isCanceled ? "The download was cancelled." : "The download was interrupted."
            onFail?(NSError(
                domain: NSURLErrorDomain,
                code: download.isCanceled ? NSURLErrorCancelled : NSURLErrorNetworkConnectionLost,
                userInfo: [NSLocalizedDescriptionKey: reason]
            ))
        }
    }
}
