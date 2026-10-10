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
            // Chromium (P2): clear the Space's CEF profile here once CEF-backed pages exist.
            completion?()
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
