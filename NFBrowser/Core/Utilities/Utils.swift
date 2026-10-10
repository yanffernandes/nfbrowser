import Foundation

func extractDomainOrIP(from text: String) -> String? {
    guard let url = URL(string: text.hasPrefix("http") ? text : "https://\(text)") else {
        return nil
    }

    guard let host = url.host else {
        return nil
    }

    return host
}

func isValidURL(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("file://") {
        return true
    }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return true
        }
    }
    if isInlineSchemeURL(trimmed) {
        return true
    }

    guard let host = extractDomainOrIP(from: trimmed) else { return false }

    if host == "localhost" {
        return true
    }

    let ipPattern = #"^(\d{1,3}\.){3}\d{1,3}$"#
    if host.range(of: ipPattern, options: .regularExpression) != nil {
        return true
    }

    let domainPattern =
        #"^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)+$"#

    return host.range(of: domainPattern, options: .regularExpression) != nil
}

func constructURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("file://") {
        if let url = URL(string: trimmed) {
            return url
        }
        let path = String(trimmed.dropFirst("file://".count))
        let decodedPath = path.removingPercentEncoding ?? path
        return URL(fileURLWithPath: decodedPath)
    }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return URL(fileURLWithPath: expanded)
        }
    }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || isInlineSchemeURL(trimmed) {
        return URL(string: trimmed)
    }
    guard isValidURL(trimmed) else { return nil }
    let host = extractDomainOrIP(from: trimmed)
    let scheme = (host == "localhost") ? "http" : "https"
    return URL(string: "\(scheme)://\(trimmed)")
}

/// `about:blank` and `data:text/html,...` are URLs; `data: science jobs` is a search.
private func isInlineSchemeURL(_ text: String) -> Bool {
    guard let scheme = ["about:", "data:"].first(where: { text.hasPrefix($0) }) else { return false }
    guard let payloadStart = text.dropFirst(scheme.count).first else { return false }
    return !payloadStart.isWhitespace
}
