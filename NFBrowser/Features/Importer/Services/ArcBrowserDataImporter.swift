import CommonCrypto
import CryptoKit
import Foundation
import SQLite3

struct ArcCookieImportRecord: Sendable {
    let domain: String
    let name: String
    let value: String
    let path: String
    let expiresAt: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
    let profilePriority: Int
    let lastUpdatedAt: Date
}

struct PasswordImportRecord: Sendable {
    let url: URL
    let username: String
    let password: String
    let createdAt: Date
    let lastUsedAt: Date?
}

struct ArcDownloadImportRecord: Sendable {
    let url: URL
    let fileName: String
    let targetPath: String
    let fileSize: Int64
    let downloadedBytes: Int64
    let state: Int
    let startedAt: Date
    let completedAt: Date?
}

struct ArcBrowserSnapshot: Sendable {
    let profileCount: Int
    let cookies: [ArcCookieImportRecord]
    let passwords: [PasswordImportRecord]
    let downloads: [ArcDownloadImportRecord]
    let skippedCookies: Int
    let skippedPasswords: Int
    let databaseFailures: Int
}

enum ArcImportIdentity {
    static func stableUUID(for sourceID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(sourceID.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

private struct ArcCookieKey: Hashable {
    let domain: String
    let name: String
    let path: String
}

private struct ArcCookieCandidate {
    let cookie: ArcCookieImportRecord
    let priority: Int
}

private final class ArcSQLiteReader {
    private var database: OpaquePointer?

    init(url: URL) throws {
        var handle: OpaquePointer?
        let databaseURI = url.absoluteString + "?mode=ro&immutable=1"
        let status = databaseURI.withCString { value in
            sqlite3_open_v2(
                value,
                &handle,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }

        guard status == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw ArcImportError.databaseUnavailable
        }

        database = handle
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func forEachRow(_ sql: String, _ body: (OpaquePointer) -> Void) throws {
        guard let database else {
            throw ArcImportError.databaseUnavailable
        }

        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw ArcImportError.databaseUnavailable
        }
        defer { sqlite3_finalize(statement) }

        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return
            }
            guard status == SQLITE_ROW else {
                throw ArcImportError.databaseUnavailable
            }
            body(statement)
        }
    }
}

private enum ArcImportError: Error {
    case arcDataNotFound
    case databaseUnavailable
    case safeStorageUnavailable
    case unsupportedEncryption
}

enum ArcBrowserDataImporter {
    private static let chromeEpochOffset: Double = 11_644_473_600
    private static let cookieVersionPrefix = Data("v10".utf8)
    private static let safeStorageService = "Arc Safe Storage"
    private static let safeStorageAccount = "Arc"

    // The snapshot stays cohesive so per-profile fallback, deduplication, and failure counts remain consistent.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func loadSnapshot() throws -> ArcBrowserSnapshot {
        let arcDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Arc", isDirectory: true)
        let userDataDirectory = arcDirectory.appendingPathComponent("User Data", isDirectory: true)
        guard FileManager.default.fileExists(atPath: userDataDirectory.path) else {
            throw ArcImportError.arcDataNotFound
        }

        let activeProfile = activeProfileName(in: userDataDirectory)
        let profileDirectories = try FileManager.default.contentsOfDirectory(
            at: userDataDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory && ["History", "Cookies", "Login Data"].contains { file in
                FileManager.default.fileExists(atPath: url.appendingPathComponent(file).path)
            }
        }
        .sorted { lhs, rhs in
            if lhs.lastPathComponent == activeProfile {
                return true
            }
            if rhs.lastPathComponent == activeProfile {
                return false
            }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        guard !profileDirectories.isEmpty else {
            throw ArcImportError.arcDataNotFound
        }

        let key = try safeStorageKey()
        var cookiesByKey: [ArcCookieKey: ArcCookieCandidate] = [:]
        var passwordsByKey: [String: PasswordImportRecord] = [:]
        var downloadsByKey: [String: ArcDownloadImportRecord] = [:]
        var skippedCookies = 0
        var skippedPasswords = 0
        var databaseFailures = 0

        for profileDirectory in profileDirectories {
            let isActiveProfile = profileDirectory.lastPathComponent == activeProfile

            let cookiesURL = profileDirectory.appendingPathComponent("Cookies")
            if FileManager.default.fileExists(atPath: cookiesURL.path) {
                do {
                    let reader = try ArcSQLiteReader(url: cookiesURL)
                    var databaseVersion = 0
                    try? reader.forEachRow("SELECT value FROM meta WHERE key = 'version' LIMIT 1") { row in
                        databaseVersion = Int(sqliteText(row, 0)) ?? Int(sqliteInteger(row, 0))
                    }

                    try reader.forEachRow(
                        "SELECT host_key, name, value, encrypted_value, path, expires_utc, " +
                            "is_secure, is_httponly, has_expires, top_frame_site_key, last_update_utc " +
                            "FROM cookies"
                    ) { row in
                        let domain = sqliteText(row, 0)
                        let name = sqliteText(row, 1)
                        let plaintextValue = sqliteText(row, 2)
                        let encryptedValue = sqliteBlob(row, 3)
                        let path = sqliteText(row, 4).isEmpty ? "/" : sqliteText(row, 4)
                        let hasExpiry = sqliteInteger(row, 8) != 0
                        let topFrameSiteKey = sqliteText(row, 9)
                        let expiresAt = hasExpiry ? chromeDate(sqliteInteger(row, 5)) : nil

                        guard !domain.isEmpty, !name.isEmpty,
                              topFrameSiteKey.isEmpty,
                              expiresAt.map({ $0 > Date() }) ?? true
                        else {
                            skippedCookies += 1
                            return
                        }

                        do {
                            var clearValue = encryptedValue.isEmpty
                                ? Data(plaintextValue.utf8)
                                : try decrypt(encryptedValue, key: key)

                            if !encryptedValue.isEmpty, databaseVersion >= 24 {
                                let domainHash = Data(SHA256.hash(data: Data(domain.utf8)))
                                guard clearValue.starts(with: domainHash) else {
                                    skippedCookies += 1
                                    return
                                }
                                clearValue.removeFirst(domainHash.count)
                            }

                            guard let value = String(data: clearValue, encoding: .utf8) else {
                                skippedCookies += 1
                                return
                            }

                            let candidate = ArcCookieImportRecord(
                                domain: domain,
                                name: name,
                                value: value,
                                path: path,
                                expiresAt: expiresAt,
                                isSecure: sqliteInteger(row, 6) != 0,
                                isHTTPOnly: sqliteInteger(row, 7) != 0,
                                profilePriority: isActiveProfile ? 2 : 1,
                                lastUpdatedAt: chromeDate(sqliteInteger(row, 10)) ?? .distantPast
                            )
                            let cookieKey = ArcCookieKey(domain: domain.lowercased(), name: name, path: path)
                            if let existing = cookiesByKey[cookieKey] {
                                if candidate.profilePriority > existing.priority ||
                                    (candidate.profilePriority == existing.priority &&
                                        candidate.lastUpdatedAt > existing.cookie.lastUpdatedAt)
                                {
                                    cookiesByKey[cookieKey] = ArcCookieCandidate(
                                        cookie: candidate,
                                        priority: candidate.profilePriority
                                    )
                                }
                            } else {
                                cookiesByKey[cookieKey] = ArcCookieCandidate(
                                    cookie: candidate,
                                    priority: candidate.profilePriority
                                )
                            }
                        } catch {
                            skippedCookies += 1
                        }
                    }
                } catch {
                    databaseFailures += 1
                }
            }

            let loginURL = profileDirectory.appendingPathComponent("Login Data")
            if FileManager.default.fileExists(atPath: loginURL.path) {
                do {
                    let reader = try ArcSQLiteReader(url: loginURL)
                    try reader.forEachRow(
                        "SELECT origin_url, username_value, password_value, date_created, " +
                            "date_last_used, blacklisted_by_user FROM logins " +
                            "WHERE length(password_value) > 0 AND blacklisted_by_user = 0"
                    ) { row in
                        let origin = sqliteText(row, 0)
                        let username = sqliteText(row, 1)
                        guard let url = URL(string: origin),
                              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                        else {
                            skippedPasswords += 1
                            return
                        }

                        do {
                            let clearValue = try decrypt(sqliteBlob(row, 2), key: key)
                            guard let password = String(data: clearValue, encoding: .utf8), !password.isEmpty else {
                                skippedPasswords += 1
                                return
                            }

                            let record = PasswordImportRecord(
                                url: url,
                                username: username,
                                password: password,
                                createdAt: chromeDate(sqliteInteger(row, 3)) ?? Date(),
                                lastUsedAt: chromeDate(sqliteInteger(row, 4))
                            )
                            let key = passwordKey(for: url, username: username)
                            if let existing = passwordsByKey[key] {
                                let existingDate = existing.lastUsedAt ?? existing.createdAt
                                let newDate = record.lastUsedAt ?? record.createdAt
                                if newDate > existingDate {
                                    passwordsByKey[key] = record
                                }
                            } else {
                                passwordsByKey[key] = record
                            }
                        } catch {
                            skippedPasswords += 1
                        }
                    }
                } catch {
                    databaseFailures += 1
                }
            }

            let downloadsURL = profileDirectory.appendingPathComponent("History")
            if FileManager.default.fileExists(atPath: downloadsURL.path) {
                do {
                    let reader = try ArcSQLiteReader(url: downloadsURL)
                    try reader.forEachRow(
                        "SELECT d.current_path, d.target_path, d.start_time, d.received_bytes, " +
                            "d.total_bytes, d.state, d.end_time, " +
                            "COALESCE((SELECT url FROM downloads_url_chains c WHERE c.id = d.id " +
                            "ORDER BY c.chain_index LIMIT 1), d.site_url) FROM downloads d"
                    ) { row in
                        let urlString = sqliteText(row, 7)
                        guard let url = URL(string: urlString),
                              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                        else {
                            return
                        }

                        let currentPath = sqliteText(row, 0)
                        let targetPath = sqliteText(row, 1)
                        let displayPath = currentPath.isEmpty ? targetPath : currentPath
                        let fileName = URL(fileURLWithPath: displayPath).lastPathComponent
                        let normalizedFileName = fileName.isEmpty ? "Downloaded file" : fileName
                        let startedAt = chromeDate(sqliteInteger(row, 2)) ?? .distantPast
                        let record = ArcDownloadImportRecord(
                            url: url,
                            fileName: normalizedFileName,
                            targetPath: FileManager.default.fileExists(atPath: currentPath)
                                ? currentPath
                                : targetPath,
                            fileSize: sqliteInteger(row, 4),
                            downloadedBytes: sqliteInteger(row, 3),
                            state: Int(sqliteInteger(row, 5)),
                            startedAt: startedAt,
                            completedAt: chromeDate(sqliteInteger(row, 6))
                        )
                        let key = "\(url.absoluteString)|\(record.fileName)|\(startedAt.timeIntervalSince1970)"
                        downloadsByKey[key] = record
                    }
                } catch {
                    databaseFailures += 1
                }
            }
        }

        return ArcBrowserSnapshot(
            profileCount: profileDirectories.count,
            cookies: cookiesByKey.values.map(\.cookie),
            passwords: Array(passwordsByKey.values),
            downloads: Array(downloadsByKey.values),
            skippedCookies: skippedCookies,
            skippedPasswords: skippedPasswords,
            databaseFailures: databaseFailures
        )
    }

    private static func activeProfileName(in userDataDirectory: URL) -> String {
        let localStateURL = userDataDirectory.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStateURL),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = state["profile"] as? [String: Any]
        else {
            return "Default"
        }
        return profile["last_used"] as? String ?? "Default"
    }

    private static func safeStorageKey() throws -> [UInt8] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", safeStorageService,
            "-a", safeStorageAccount,
            "-w"
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let secretData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let secret = String(data: secretData, encoding: .utf8)?
              .trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty
        else {
            throw ArcImportError.safeStorageUnavailable
        }

        let password = Array(secret.utf8)
        let salt = Array("saltysalt".utf8)
        var derivedKey = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let status = password.withUnsafeBufferPointer { passwordBuffer in
            salt.withUnsafeBufferPointer { saltBuffer in
                derivedKey.withUnsafeMutableBufferPointer { keyBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        UnsafeRawPointer(passwordBuffer.baseAddress!).assumingMemoryBound(to: Int8.self),
                        passwordBuffer.count,
                        saltBuffer.baseAddress,
                        saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBuffer.baseAddress,
                        keyBuffer.count
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw ArcImportError.safeStorageUnavailable
        }
        return derivedKey
    }

    private static func decrypt(_ value: Data, key: [UInt8]) throws -> Data {
        guard value.starts(with: cookieVersionPrefix) else {
            if value.starts(with: Data("v".utf8)) {
                throw ArcImportError.unsupportedEncryption
            }
            return value
        }

        let ciphertext = Array(value.dropFirst(cookieVersionPrefix.count))
        guard !ciphertext.isEmpty, ciphertext.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw ArcImportError.unsupportedEncryption
        }

        let initializationVector = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var clearValue = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        let clearValueCapacity = clearValue.count
        var bytesMoved = 0
        let status: CCCryptorStatus = key.withUnsafeBytes { keyBuffer in
            initializationVector.withUnsafeBytes { ivBuffer in
                ciphertext.withUnsafeBytes { ciphertextBuffer in
                    clearValue.withUnsafeMutableBytes { outputBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress,
                            key.count,
                            ivBuffer.baseAddress,
                            ciphertextBuffer.baseAddress,
                            ciphertext.count,
                            outputBuffer.baseAddress,
                            clearValueCapacity,
                            &bytesMoved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ArcImportError.unsupportedEncryption
        }
        return Data(clearValue.prefix(bytesMoved))
    }

    private static func chromeDate(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(value) / 1_000_000 - chromeEpochOffset)
    }

    private static func passwordKey(for url: URL, username: String) -> String {
        let scheme = url.scheme?.lowercased() ?? "https"
        let host = url.host?.lowercased() ?? ""
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)|\(username.lowercased())"
    }
}

private func sqliteText(_ statement: OpaquePointer, _ column: Int32) -> String {
    guard let value = sqlite3_column_text(statement, column) else { return "" }
    return String(cString: value)
}

private func sqliteInteger(_ statement: OpaquePointer, _ column: Int32) -> Int64 {
    sqlite3_column_int64(statement, column)
}

private func sqliteBlob(_ statement: OpaquePointer, _ column: Int32) -> Data {
    let length = Int(sqlite3_column_bytes(statement, column))
    guard length > 0, let value = sqlite3_column_blob(statement, column) else { return Data() }
    return Data(bytes: value, count: length)
}
