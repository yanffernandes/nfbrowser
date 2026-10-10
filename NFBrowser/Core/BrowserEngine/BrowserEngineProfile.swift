import Foundation
@preconcurrency import WebKit

final class BrowserEngineProfile {
    let engineKind: BrowserEngineKind
    let identifier: UUID
    let isPrivate: Bool

    /// Created on first use, so a Space only gets a WebKit store when WebKit code asks for one.
    private(set) lazy var dataStore: WKWebsiteDataStore = isPrivate
        ? WKWebsiteDataStore.nonPersistent()
        : WKWebsiteDataStore(forIdentifier: identifier)

    init(engineKind: BrowserEngineKind = .webkit, identifier: UUID, isPrivate: Bool) {
        self.engineKind = engineKind
        self.identifier = identifier
        self.isPrivate = isPrivate
    }

    func clearData(
        ofTypes types: Set<BrowserWebsiteDataType>,
        forHost host: String? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard engineKind == .webkit else {
            clearChromiumData(ofTypes: types, forHost: host, completion: completion)
            return
        }

        let mappedTypes = mapWebsiteDataTypes(types)
        guard let host, !host.isEmpty else {
            dataStore.removeData(ofTypes: mappedTypes, modifiedSince: .distantPast) {
                completion?()
            }
            return
        }

        dataStore.fetchDataRecords(ofTypes: mappedTypes) { records in
            let targetRecords = records.filter { $0.displayName.contains(host) }
            guard !targetRecords.isEmpty else {
                completion?()
                return
            }

            self.dataStore.removeData(ofTypes: mappedTypes, for: targetRecords) {
                completion?()
            }
        }
    }

    /// Adds cookies to this profile's store and returns how many the engine accepted.
    @MainActor
    func importCookies(_ cookies: [HTTPCookie]) async -> Int {
        guard !cookies.isEmpty else { return 0 }
        switch engineKind {
        case .webkit:
            let cookieStore = dataStore.httpCookieStore
            for cookie in cookies {
                await cookieStore.setCookie(cookie)
            }
            return cookies.count
        case .chromium:
            return await withCheckedContinuation { continuation in
                NFChromiumRuntime.shared.setCookies(
                    cookies,
                    forProfile: identifier.uuidString,
                    persistent: !isPrivate
                ) { accepted in
                    continuation.resume(returning: accepted)
                }
            }
        }
    }

    /// Chromium has no per-site storage removal outside a page, so clearing everything
    /// for the Space also removes its profile directory (now or at the next launch).
    private func clearChromiumData(
        ofTypes types: Set<BrowserWebsiteDataType>,
        forHost host: String?,
        completion: (() -> Void)?
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.clearChromiumData(ofTypes: types, forHost: host, completion: completion)
            }
            return
        }
        let runtime = NFChromiumRuntime.shared
        let profileIdentifier = identifier.uuidString
        let clearsEverything = types.contains(.all)
        if clearsEverything, host == nil, !runtime.isRunning {
            // Nothing has the profile's files open, so it can go without starting Chromium.
            runtime.removeProfile(profileIdentifier)
            completion?()
            return
        }
        let group = DispatchGroup()
        if clearsEverything || types.contains(.cookies) {
            group.enter()
            runtime.deleteCookies(forProfile: profileIdentifier, persistent: !isPrivate, host: host) {
                group.leave()
            }
        }
        if clearsEverything || types.contains(.cache) {
            group.enter()
            runtime.clearCache(forProfile: profileIdentifier, persistent: !isPrivate) {
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if clearsEverything, host == nil {
                runtime.removeProfile(profileIdentifier)
            }
            completion?()
        }
    }

    private func mapWebsiteDataTypes(_ types: Set<BrowserWebsiteDataType>) -> Set<String> {
        if types.contains(.all) {
            return WKWebsiteDataStore.allWebsiteDataTypes()
        }

        var mapped: Set<String> = []
        if types.contains(.cookies) {
            mapped.insert(WKWebsiteDataTypeCookies)
        }
        if types.contains(.cache) {
            mapped.formUnion([
                WKWebsiteDataTypeDiskCache,
                WKWebsiteDataTypeMemoryCache,
                WKWebsiteDataTypeFetchCache
            ])
        }
        return mapped
    }
}
