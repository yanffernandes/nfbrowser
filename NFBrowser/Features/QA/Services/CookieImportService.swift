import CommonCrypto
import Foundation
import SQLite3
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

    /// Import cookies from the local Google Chrome installation into a specific container
    func importFromChrome(
        into spaceID: UUID,
        domainFilter: String? = nil
    ) async throws -> Int {
        let cookies = try await Task.detached(priority: .userInitiated) {
            try ChromeCookieExtractor.readCookies(domainFilter: domainFilter)
        }.value

        let profile = BrowserEngine.shared.makeProfile(identifier: spaceID, isPrivate: false)
        let cookieStore = profile.dataStore.httpCookieStore
        return await injectCookies(cookies, into: cookieStore)
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

private enum ChromeCookieExtractor {
    private static let chromeEpochOffset: Double = 11_644_473_600
    private static let cookieVersionPrefix = Data("v10".utf8)

    static func readCookies(domainFilter: String? = nil) throws -> [HTTPCookie] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let possiblePaths = [
            home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies"),
            home.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Network/Cookies"),
            home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies"),
            home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Default/Network/Cookies")
        ]

        guard let cookiePath = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw NSError(domain: "ChromeImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Chrome cookies database not found"])
        }

        let key = try safeStorageKey()
        var database: OpaquePointer?
        let dbURI = cookiePath.absoluteString + "?mode=ro&immutable=1"
        let status = dbURI.withCString { sqlite3_open_v2($0, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX, nil) }
        guard status == SQLITE_OK, let db = database else {
            if let database { sqlite3_close(database) }
            throw NSError(domain: "ChromeImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not open Chrome database"])
        }
        defer { sqlite3_close(db) }

        var cookies: [HTTPCookie] = []
        let query = "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly FROM cookies"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
            throw NSError(domain: "ChromeImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not prepare Chrome cookie query"])
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let hostC = sqlite3_column_text(statement, 0),
                  let nameC = sqlite3_column_text(statement, 1) else {
                continue
            }
            let host = String(cString: hostC)
            let name = String(cString: nameC)
            var value = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            let blobBytes = sqlite3_column_blob(statement, 3)
            let blobLen = Int(sqlite3_column_bytes(statement, 3))
            let path = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "/"
            let expiresUtc = sqlite3_column_int64(statement, 5)
            let isSecure = sqlite3_column_int(statement, 6) != 0
            let isHttpOnly = sqlite3_column_int(statement, 7) != 0

            if value.isEmpty && blobBytes != nil && blobLen > 0 {
                let data = Data(bytes: blobBytes!, count: blobLen)
                if let decrypted = try? decrypt(data, key: key), let str = String(data: decrypted, encoding: .utf8) {
                    value = str
                }
            }

            if let domainFilter, !domainFilter.isEmpty {
                let cleanFilter = domainFilter.lowercased().replacingOccurrences(of: "www.", with: "")
                let cleanDomain = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if !cleanDomain.contains(cleanFilter) && !cleanFilter.contains(cleanDomain) {
                    continue
                }
            }

            var props: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .name: name,
                .value: value,
                .path: path.isEmpty ? "/" : path,
                .secure: isSecure ? "TRUE" : "FALSE"
            ]
            if expiresUtc > 0 {
                props[.expires] = Date(timeIntervalSince1970: Double(expiresUtc) / 1_000_000 - chromeEpochOffset)
            }
            if isHttpOnly {
                props[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
            }
            if let cookie = HTTPCookie(properties: props) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    private static func safeStorageKey() throws -> [UInt8] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-w",
            "-s", "Chrome Safe Storage",
            "-a", "Chrome"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let secret = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            throw NSError(domain: "ChromeImport", code: 4, userInfo: [NSLocalizedDescriptionKey: "Chrome Safe Storage password unavailable"])
        }

        let password = Array(secret.utf8)
        let salt = Array("saltysalt".utf8)
        var derivedKey = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = password.withUnsafeBufferPointer { pBuf in
            salt.withUnsafeBufferPointer { sBuf in
                derivedKey.withUnsafeMutableBufferPointer { kBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        UnsafeRawPointer(pBuf.baseAddress!).assumingMemoryBound(to: Int8.self),
                        pBuf.count,
                        sBuf.baseAddress,
                        sBuf.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        kBuf.baseAddress,
                        kBuf.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw NSError(domain: "ChromeImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Key derivation failed"])
        }
        return derivedKey
    }

    private static func decrypt(_ value: Data, key: [UInt8]) throws -> Data {
        guard value.starts(with: cookieVersionPrefix) else {
            return value
        }
        let ciphertext = Array(value.dropFirst(cookieVersionPrefix.count))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else {
            return value
        }
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var clearValue = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let clearValueCapacity = clearValue.count
        var bytesMoved = 0
        let status = key.withUnsafeBytes { keyBuffer in
            iv.withUnsafeBytes { ivBuffer in
                ciphertext.withUnsafeBytes { cipherBuffer in
                    clearValue.withUnsafeMutableBytes { outBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            cipherBuffer.baseAddress,
                            ciphertext.count,
                            outBuffer.baseAddress,
                            clearValueCapacity,
                            &bytesMoved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            return value
        }
        return Data(clearValue.prefix(bytesMoved))
    }
}
