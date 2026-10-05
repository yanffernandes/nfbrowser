import AppKit
import Foundation
import WebKit

final class FullPageScreenshotService {
    static let shared = FullPageScreenshotService()

    private init() {}

    @MainActor
    func captureScreenshot(from webView: WKWebView, copyToClipboard: Bool = false) async throws -> URL? {
        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.afterScreenUpdates = true

        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: snapshotConfig) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(domain: "ScreenshotError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to capture snapshot"]))
                }
            }
        }

        if copyToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }

        // Save file to Downloads
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let host = webView.url?.host ?? "screenshot"
        let fileName = "\(host)_\(timestamp).png"
        let fileURL = downloads.appendingPathComponent(fileName)

        try pngData.write(to: fileURL)
        return fileURL
    }
}
