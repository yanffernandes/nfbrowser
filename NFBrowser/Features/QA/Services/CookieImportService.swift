import Foundation
import WebKit

final class CookieImportService {
    static let shared = CookieImportService()

    private init() {}

    struct JSONCookieRecord: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String?
        let secure: Bool?
        let httpOnly: Bool?
        let expirationDate: Double?
    }

    /// Import cookies from the local Arc browser installation into a specific container
    func importFromArc(
        into spaceID: UUID,
        domainFilter: String? = nil
    ) async throws -> Int {
        let snapshot = try await Task.detached(priority: .userInitiated) {
            try ArcBrowserDataImporter.loadSnapshot()
        }.value

        let records = snapshot.cookies
        let profile = BrowserEngine.shared.makeProfile(identifier: spaceID, isPrivate: false)
        let cookieStore = profile.dataStore.httpCookieStore

        var importableCookies: [HTTPCookie] = []
        for record in records {
            if let domainFilter, !domainFilter.isEmpty {
                let cleanFilter = domainFilter.lowercased().replacingOccurrences(of: "www.", with: "")
                let cleanDomain = record.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !cleanDomain.contains(cleanFilter) && !cleanFilter.contains(cleanDomain) {
                    continue
                }
            }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: record.domain,
                .name: record.name,
                .value: record.value,
                .path: record.path.isEmpty ? "/" : record.path,
                .secure: record.isSecure ? "TRUE" : "FALSE"
            ]
            if let expiresAt = record.expiresAt {
                properties[.expires] = expiresAt
            }
            if record.isHTTPOnly {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }

            if let cookie = HTTPCookie(properties: properties) {
                importableCookies.append(cookie)
            }
        }

        return await injectCookies(importableCookies, into: cookieStore)
    }

    /// Parse and filter cookies from JSON data
    func parseJSONCookies(
        data: Data,
        domainFilter: String? = nil
    ) throws -> [HTTPCookie] {
        let decoder = JSONDecoder()
        let records = try decoder.decode([JSONCookieRecord].self, from: data)

        var importableCookies: [HTTPCookie] = []
        for record in records {
            if let domainFilter, !domainFilter.isEmpty {
                let cleanFilter = domainFilter.lowercased().replacingOccurrences(of: "www.", with: "")
                let cleanDomain = record.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !cleanDomain.contains(cleanFilter) && !cleanFilter.contains(cleanDomain) {
                    continue
                }
            }

            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: record.domain,
                .name: record.name,
                .value: record.value,
                .path: record.path ?? "/",
                .secure: (record.secure ?? false) ? "TRUE" : "FALSE"
            ]
            if let exp = record.expirationDate {
                properties[.expires] = Date(timeIntervalSince1970: exp)
            }
            if record.httpOnly ?? false {
                properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }

            if let cookie = HTTPCookie(properties: properties) {
                importableCookies.append(cookie)
            }
        }
        return importableCookies
    }

    /// Import cookies from a standard JSON format (e.g. Cookie-Editor extension export)
    func importFromJSON(
        data: Data,
        into spaceID: UUID,
        domainFilter: String? = nil
    ) async throws -> Int {
        let importableCookies = try parseJSONCookies(data: data, domainFilter: domainFilter)
        let profile = BrowserEngine.shared.makeProfile(identifier: spaceID, isPrivate: false)
        let cookieStore = profile.dataStore.httpCookieStore
        return await injectCookies(importableCookies, into: cookieStore)
    }

    private func injectCookies(
        _ cookies: [HTTPCookie],
        into cookieStore: WKHTTPCookieStore
    ) async -> Int {
        guard !cookies.isEmpty else { return 0 }

        var importedCount = 0
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                cookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
            importedCount += 1
        }
        return importedCount
    }
}
