import Foundation

final class ChromeWebStoreService {
    static let shared = ChromeWebStoreService()

    private init() {}

    /// Returns the Google Web Store CRX download URL for an extension ID.
    static func crxDownloadURL(for extensionId: String) -> URL {
        let updateURLString = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D\(extensionId)%26uc"
        return URL(string: updateURLString)!
    }

    /// Extracts the 32-character extension ID from any Chrome Web Store URL.
    /// Example: https://chromewebstore.google.com/detail/cookie-editor/hlkenndednhfkekhgcdicdfddnkalmdm
    static func extractExtensionId(from url: URL) -> String? {
        let string = url.absoluteString
        guard string.contains("chromewebstore.google.com") || string.contains("chrome.google.com/webstore") else {
            return nil
        }

        let pattern = "([a-z]{32})"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: string,
                  options: [],
                  range: NSRange(location: 0, length: string.utf16.count)
              ),
              let range = Range(match.range(at: 1), in: string)
        else {
            return nil
        }

        return String(string[range]).lowercased()
    }

    func extractExtensionId(from url: URL) -> String? {
        Self.extractExtensionId(from: url)
    }

    /// Downloads the CRX file for a given Chrome Web Store extension ID.
    func downloadCRX(extensionId: String) async throws -> Data {
        let url = Self.crxDownloadURL(for: extensionId)

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              !data.isEmpty
        else {
            throw URLError(.badServerResponse)
        }

        return data
    }

    /// Downloads and extracts an extension into the given target directory.
    func downloadAndExtract(extensionId: String, destinationDirectory: URL) async throws {
        let crxData = try await downloadCRX(extensionId: extensionId)
        try CRXExtractor.extract(crxData: crxData, to: destinationDirectory)
    }
}
