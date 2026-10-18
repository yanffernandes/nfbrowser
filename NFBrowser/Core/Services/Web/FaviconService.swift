import AppKit
import CoreImage
import FaviconFinder
import SwiftUI

final class FaviconService: ObservableObject {
    static let shared = FaviconService()
    private var cache: [String: NSImage] = [:]
    private var imageDataCache: [String: Data] = [:]
    private var colorCache: [String: Color] = [:]
    private var sourceURLCache: [String: URL] = [:]
    private var isFetching: Set<String> = []
    private var pendingCompletions: [String: [(NSImage?) -> Void]] = [:]
    private var pendingFileWrites: [String: [(URL, (URL?, Bool) -> Void)]] = [:]
    private let lock = NSLock()

    var persistentFaviconDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NFBrowser/Favicons", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var legacyFaviconDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("Favicons", isDirectory: true)
    }

    func persistentURL(forDomain domain: String) -> URL {
        let normalized = normalizeDomain(domain)
        let safeName = normalized
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return persistentFaviconDirectory.appendingPathComponent("\(safeName).png")
    }

    func persistentURL(forTabId id: UUID) -> URL {
        persistentFaviconDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    func isLikelyImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["ico", "png", "svg", "jpg", "jpeg", "webp", "gif"].contains(ext) {
            return true
        }
        let lower = url.absoluteString.lowercased()
        return lower.contains("favicon") || lower.contains("apple-touch-icon") || lower.contains("s2/favicons")
    }

    func cachedFavicon(
        for domain: String?,
        faviconURL: URL? = nil,
        localFileURL: URL? = nil
    ) -> NSImage? {
        let normalizedDomain = domain.flatMap { normalizeDomain($0) }

        lock.lock()
        // 1. Check in-memory cache
        if let localFileURL, let img = cache[localFileURL.path] {
            lock.unlock()
            return img
        }
        if let normalizedDomain, let img = cache[normalizedDomain] {
            lock.unlock()
            return img
        }
        if let urlKey = faviconURL?.absoluteString, let img = cache[urlKey] {
            lock.unlock()
            return img
        }
        lock.unlock()

        // 2. Check disk cache
        var candidateURLs: [URL] = []
        if let localFileURL {
            candidateURLs.append(localFileURL)
        }
        if let normalizedDomain, !normalizedDomain.isEmpty {
            candidateURLs.append(persistentURL(forDomain: normalizedDomain))
            candidateURLs.append(legacyFaviconDirectory.appendingPathComponent("\(normalizedDomain).png"))
        }

        for fileURL in candidateURLs {
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let image = NSImage(data: data) {
                lock.lock()
                if let localFileURL { cache[localFileURL.path] = image }
                if let normalizedDomain {
                    cache[normalizedDomain] = image
                    imageDataCache[normalizedDomain] = data
                }
                if let urlKey = faviconURL?.absoluteString { cache[urlKey] = image }
                lock.unlock()
                return image
            }
        }

        return nil
    }

    func getFavicon(for searchURL: String) -> NSImage? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        lock.lock()
        if let cachedFavicon = cache[domain] {
            lock.unlock()
            return cachedFavicon
        }
        lock.unlock()

        let diskFile = persistentURL(forDomain: domain)
        if FileManager.default.fileExists(atPath: diskFile.path),
           let data = try? Data(contentsOf: diskFile),
           let image = NSImage(data: data) {
            lock.lock()
            cache[domain] = image
            imageDataCache[domain] = data
            lock.unlock()
            return image
        }

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    func getFaviconColor(for searchURL: String) -> Color? {
        guard let domain = extractDomain(from: searchURL) else { return nil }

        lock.lock()
        if let cachedColor = colorCache[domain] {
            lock.unlock()
            return cachedColor
        }

        if let favicon = cache[domain] {
            let color = Color(favicon.averageColor())
            colorCache[domain] = color
            lock.unlock()
            return color
        }
        lock.unlock()

        fetchAndCacheFavicon(for: domain)
        return nil
    }

    func faviconURL(for domain: String) -> URL? {
        let normalizedDomain = normalizeDomain(domain)
        lock.lock()
        let cached = sourceURLCache[normalizedDomain]
        lock.unlock()

        if let cached {
            return cached
        }
        guard !normalizedDomain.isEmpty else { return nil }
        return URL(string: "https://\(normalizedDomain)/favicon.ico")
    }

    func faviconURL(forSearchURL searchURL: String) -> URL? {
        guard let domain = extractDomain(from: searchURL) else { return nil }
        return faviconURL(for: domain)
    }

    private func extractDomain(from searchURL: String) -> String? {
        let trimmed = searchURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed.replacingOccurrences(of: "{query}", with: "")

        if let host = URL(string: sanitized)?.host {
            return normalizeDomain(host)
        }

        if let host = URL(string: "https://\(sanitized)")?.host {
            return normalizeDomain(host)
        }

        return nil
    }

    func normalizeDomain(_ domain: String) -> String {
        let lowercased = domain.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private func canonicalURL(for domain: String) -> URL? {
        guard !domain.isEmpty else { return nil }
        return URL(string: "https://\(domain)")
    }

    func fetchFaviconSync(for searchURL: String, completion: @escaping (NSImage?) -> Void) {
        guard let domain = extractDomain(from: searchURL) else {
            completion(nil)
            return
        }

        if let cached = cachedFavicon(for: domain) {
            completion(cached)
            return
        }

        fetchAndCacheFavicon(for: domain, completion: completion)
    }

    func downloadAndCacheFavicon(
        from remoteURL: URL,
        domain: String?,
        localFileURL: URL? = nil,
        completion: ((NSImage?) -> Void)? = nil
    ) {
        let normalizedDomain = domain.map { normalizeDomain($0) }

        if remoteURL.isFileURL {
            if let image = NSImage(contentsOf: remoteURL) {
                lock.lock()
                if let normalizedDomain {
                    cache[normalizedDomain] = image
                }
                if let localFileURL {
                    cache[localFileURL.path] = image
                }
                lock.unlock()
                completion?(image)
                return
            }
        }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: remoteURL)
                request.timeoutInterval = 8.0
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                    forHTTPHeaderField: "User-Agent"
                )

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      !data.isEmpty,
                      let image = NSImage(data: data)
                else {
                    await MainActor.run { completion?(nil) }
                    return
                }

                if let localFileURL {
                    try? data.write(to: localFileURL, options: .atomic)
                }
                if let normalizedDomain, !normalizedDomain.isEmpty {
                    let domainFile = self.persistentURL(forDomain: normalizedDomain)
                    try? data.write(to: domainFile, options: .atomic)
                }

                await MainActor.run {
                    self.lock.lock()
                    if let normalizedDomain {
                        self.cache[normalizedDomain] = image
                        self.imageDataCache[normalizedDomain] = data
                        self.sourceURLCache[normalizedDomain] = remoteURL
                        self.colorCache[normalizedDomain] = Color(image.averageColor())
                    }
                    if let localFileURL {
                        self.cache[localFileURL.path] = image
                    }
                    self.cache[remoteURL.absoluteString] = image
                    self.lock.unlock()
                    self.objectWillChange.send()
                    completion?(image)
                }
            } catch {
                await MainActor.run { completion?(nil) }
            }
        }
    }

    private func fetchAndCacheFavicon(for domain: String, completion: ((NSImage?) -> Void)? = nil) {
        lock.lock()
        if let cachedFavicon = cache[domain] {
            lock.unlock()
            completion?(cachedFavicon)
            return
        }

        if let completion {
            pendingCompletions[domain, default: []].append(completion)
        }

        guard !isFetching.contains(domain) else {
            lock.unlock()
            return
        }
        isFetching.insert(domain)
        lock.unlock()

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let payload = await self.fetchFaviconPayload(for: domain)
            await MainActor.run {
                self.completeFetch(
                    for: domain,
                    favicon: payload?.image,
                    sourceURL: payload?.sourceURL,
                    imageData: payload?.data
                )
            }
        }
    }

    @MainActor
    private func completeFetch(for domain: String, favicon: NSImage?, sourceURL: URL?, imageData: Data?) {
        lock.lock()
        if let favicon {
            cache[domain] = favicon
            colorCache[domain] = Color(favicon.averageColor())
            if let sourceURL {
                sourceURLCache[domain] = sourceURL
            }
            objectWillChange.send()
        }
        if let imageData {
            imageDataCache[domain] = imageData
            let domainFile = persistentURL(forDomain: domain)
            try? imageData.write(to: domainFile, options: .atomic)
        }

        isFetching.remove(domain)
        let completions = pendingCompletions.removeValue(forKey: domain) ?? []
        let fileWrites = pendingFileWrites.removeValue(forKey: domain) ?? []
        lock.unlock()

        for completion in completions {
            completion(favicon)
        }

        for (url, completion) in fileWrites {
            guard let imageData = imageDataCache[domain] else {
                completion(nil, false)
                continue
            }
            do {
                try imageData.write(to: url, options: .atomic)
                completion(sourceURL ?? faviconURL(for: domain), true)
            } catch {
                completion(nil, false)
            }
        }
    }

    private func fetchFaviconPayload(for domain: String) async -> (image: NSImage, data: Data, sourceURL: URL)? {
        guard let siteURL = canonicalURL(for: domain) else { return nil }

        // 1. Try FaviconFinder
        do {
            let favicon = try await FaviconFinder(url: siteURL)
                .fetchFaviconURLs()
                .download()
                .largest()
            if let faviconImage = favicon.image {
                return (faviconImage.image, faviconImage.data, favicon.url.source)
            }
        } catch {}

        // 2. Direct fallback to https://<domain>/favicon.ico
        if let directURL = URL(string: "https://\(domain)/favicon.ico") {
            if let result = await downloadImagePayload(from: directURL) {
                return result
            }
        }

        // 3. Fallback to Google S2 Favicon service
        if let googleURL = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=64") {
            if let result = await downloadImagePayload(from: googleURL) {
                return result
            }
        }

        return nil
    }

    private func downloadImagePayload(from url: URL) async -> (image: NSImage, data: Data, sourceURL: URL)? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 6.0
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  !data.isEmpty,
                  let image = NSImage(data: data)
            else {
                return nil
            }
            return (image, data, url)
        } catch {
            return nil
        }
    }

    func downloadAndSaveFavicon(
        for domain: String,
        faviconURL: URL,
        to saveURL: URL,
        completion: @escaping (URL?, Bool) -> Void
    ) {
        let normalizedDomain = normalizeDomain(domain)

        // 1. Check in-memory image data
        if let data = imageDataCache[normalizedDomain] ?? pngData(from: cache[normalizedDomain]) {
            do {
                try data.write(to: saveURL, options: .atomic)
                let domainURL = persistentURL(forDomain: normalizedDomain)
                try? data.write(to: domainURL, options: .atomic)
                completion(self.faviconURL(for: normalizedDomain), true)
            } catch {
                completion(nil, false)
            }
            return
        }

        // 2. Check persistent disk cache for domain
        let domainFile = persistentURL(forDomain: normalizedDomain)
        if FileManager.default.fileExists(atPath: domainFile.path),
           let data = try? Data(contentsOf: domainFile),
           let image = NSImage(data: data) {
            lock.lock()
            cache[normalizedDomain] = image
            imageDataCache[normalizedDomain] = data
            lock.unlock()
            do {
                try data.write(to: saveURL, options: .atomic)
                completion(self.faviconURL(for: normalizedDomain), true)
            } catch {
                completion(nil, false)
            }
            return
        }

        // 3. If a direct remote image URL was provided
        if isLikelyImageURL(faviconURL) {
            downloadAndCacheFavicon(from: faviconURL, domain: normalizedDomain, localFileURL: saveURL) { image in
                if image != nil {
                    completion(faviconURL, true)
                } else {
                    self.fetchViaFaviconFinder(for: normalizedDomain, saveURL: saveURL, completion: completion)
                }
            }
            return
        }

        // 4. Otherwise use FaviconFinder + fallbacks
        fetchViaFaviconFinder(for: normalizedDomain, saveURL: saveURL, completion: completion)
    }

    private func fetchViaFaviconFinder(
        for domain: String,
        saveURL: URL,
        completion: @escaping (URL?, Bool) -> Void
    ) {
        lock.lock()
        pendingFileWrites[domain, default: []].append((saveURL, completion))
        guard !isFetching.contains(domain) else {
            lock.unlock()
            return
        }
        isFetching.insert(domain)
        lock.unlock()

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let payload = await self.fetchFaviconPayload(for: domain)
            await MainActor.run {
                self.completeFetch(
                    for: domain,
                    favicon: payload?.image,
                    sourceURL: payload?.sourceURL,
                    imageData: payload?.data
                )
            }
        }
    }

    private func pngData(from image: NSImage?) -> Data? {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension NSImage {
    func averageColor() -> NSColor {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return NSColor.gray
        }

        let inputImage = CIImage(cgImage: cgImage)
        let extentVector = CIVector(
            x: inputImage.extent.origin.x,
            y: inputImage.extent.origin.y,
            z: inputImage.extent.size.width,
            w: inputImage.extent.size.height
        )

        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [kCIInputImageKey: inputImage, kCIInputExtentKey: extentVector]
        ) else {
            return NSColor.gray
        }

        guard let outputImage = filter.outputImage else {
            return NSColor.gray
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: CGFloat(bitmap[3]) / 255
        )
    }
}
