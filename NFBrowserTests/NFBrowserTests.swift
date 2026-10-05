//
//  oraTests.swift
//  oraTests
//
//  Created by keni on 6/21/25.
//

import Foundation
import SwiftData
@preconcurrency import WebKit
@testable import NFBrowser
import Testing

private final class RequestCountingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var handledRequestCount = 0

    static func reset() {
        lock.lock()
        handledRequestCount = 0
        lock.unlock()
    }

    static var requestCount: Int {
        lock.lock()
        let count = handledRequestCount
        lock.unlock()
        return count
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.handledRequestCount += 1
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/filter.txt")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("||ads.example^".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct OraTests {
    @Test func normalizesHostsForPasswordMatching() {
        #expect(PasswordManagerService.normalizeHost("WWW.Example.COM.") == "www.example.com")
        #expect(PasswordManagerService.normalizeHost(" login.example.com ") == "login.example.com")
    }

    @Test func normalizesOriginsForPasswordMatching() throws {
        let secureURL = try #require(URL(string: "https://WWW.Example.COM/login"))
        let defaultPortURL = try #require(URL(string: "https://example.com:443/account"))
        let customPortURL = try #require(URL(string: "https://example.com:8443/account"))
        let insecureURL = try #require(URL(string: "http://example.com/login"))
        let unsupportedURL = try #require(URL(string: "file:///tmp/index.html"))

        #expect(PasswordManagerService.normalizedOrigin(from: secureURL) == "https://www.example.com")
        #expect(PasswordManagerService.normalizedOrigin(from: defaultPortURL) == "https://example.com")
        #expect(PasswordManagerService.normalizedOrigin(from: customPortURL) == "https://example.com:8443")
        #expect(PasswordManagerService.normalizedOrigin(from: insecureURL) == "http://example.com")
        #expect(PasswordManagerService.normalizedOrigin(from: unsupportedURL) == nil)
    }

    @Test func generatesStrongPasswords() {
        let password = PasswordManagerService.generateStrongPassword()

        #expect(password.count >= 12)
        #expect(password.contains("-") || password.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    @Test func warnsBeforeSavingPasswordsOnInsecurePages() throws {
        let insecureURL = try #require(URL(string: "http://example.com/login"))

        let prompt = PasswordAutofillCoordinator.savePromptDetails(
            for: insecureURL,
            username: "alice@example.com",
            normalizedHost: "example.com",
            isUpdate: false
        )

        #expect(prompt.showsSecurityWarning)
        #expect(prompt.title == "Save Password on Insecure Page")
        #expect(prompt.confirmButtonTitle == "Save Anyway")
        #expect(prompt.neverButtonTitle == "Never on This Site")
        #expect(prompt.message.contains("insecure connection (http://)"))
    }

    @Test func keepsStandardPromptOnSecurePages() throws {
        let secureURL = try #require(URL(string: "https://example.com/login"))

        let prompt = PasswordAutofillCoordinator.savePromptDetails(
            for: secureURL,
            username: "",
            normalizedHost: "example.com",
            isUpdate: true
        )

        #expect(prompt.showsSecurityWarning == false)
        #expect(prompt.title == "Update Password")
        #expect(prompt.confirmButtonTitle == "Update Password")
        #expect(prompt.neverButtonTitle == "Never on This Site")
        #expect(prompt.message == "Update the saved password for example.com?")
    }

    @Test func recognizesEmailUsernamesForSignupSuggestions() {
        #expect(PasswordManagerService.looksLikeEmail("alice@example.com"))
        #expect(PasswordManagerService.looksLikeEmail(" alice@example.com "))
        #expect(PasswordManagerService.looksLikeEmail("alice") == false)
        #expect(PasswordManagerService.looksLikeEmail("alice@localhost") == false)
    }

    @Test func limitsSignupSuggestionsByFocusedFieldKind() {
        let entry = SavedPasswordSummary(
            metadata: SavedPasswordMetadata(
                id: "entry-1",
                origin: "https://example.com",
                host: "example.com",
                username: "saved@example.com",
                createdAt: .distantPast,
                updatedAt: .distantPast,
                lastUsedAt: nil
            ),
            persistentReference: Data()
        )
        let emailSuggestion = PasswordEmailSuggestion(
            email: "person@example.com",
            host: "another.com",
            lastUsedAt: nil,
            updatedAt: .distantPast
        )

        let passwordFocus = PasswordBridgeFocusPayload(
            fieldID: "password-field",
            hostname: "example.com",
            action: .createAccount,
            fieldKind: .password,
            usernameFieldID: "email-field",
            passwordFieldIDs: ["password-field"],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 100, height: 20)
        )
        let passwordSuggestions = PasswordAutofillCoordinator.resolveSuggestions(
            for: passwordFocus,
            matchingEntries: [entry],
            emailSuggestions: [emailSuggestion],
            generatedPassword: "StrongPass123!"
        )

        #expect(passwordSuggestions.generatedPassword == "StrongPass123!")
        #expect(passwordSuggestions.savedPasswordEntries.isEmpty)
        #expect(passwordSuggestions.emailSuggestions.isEmpty)

        let emailFocus = PasswordBridgeFocusPayload(
            fieldID: "email-field",
            hostname: "example.com",
            action: .createAccount,
            fieldKind: .email,
            usernameFieldID: "email-field",
            passwordFieldIDs: ["password-field"],
            rect: PasswordBridgeRect(originX: 0, originY: 0, width: 100, height: 20)
        )
        let emailSuggestions = PasswordAutofillCoordinator.resolveSuggestions(
            for: emailFocus,
            matchingEntries: [entry],
            emailSuggestions: [emailSuggestion],
            generatedPassword: "StrongPass123!"
        )

        #expect(emailSuggestions.generatedPassword == nil)
        #expect(emailSuggestions.savedPasswordEntries.isEmpty)
        #expect(emailSuggestions.emailSuggestions == [emailSuggestion])
    }

    @Test func storesPrivacySettingsPerSpaceIndependently() {
        let store = SettingsStore.shared
        let firstContainerID = UUID()
        let secondContainerID = UUID()
        let baselineSecondSettings = store.privacySettings(for: secondContainerID)

        defer {
            store.removeContainerSettings(for: firstContainerID)
            store.removeContainerSettings(for: secondContainerID)
        }

        let updatedSettings = SpacePrivacySettings(
            blockThirdPartyTrackers: true,
            blockFingerprinting: true,
            adBlocking: true,
            adBlock: SpaceAdBlockSettings(
                enabled: true,
                enabledBuiltinListIDs: [
                    FilterListCatalogService.adGuardBaseID,
                    FilterListCatalogService.adGuardAnnoyancesID
                ],
                enabledCustomListIDs: ["custom-test-list"],
                updateMode: .aggressiveAuto
            ),
            cookiesPolicy: .blockThirdParty
        )

        store.setPrivacySettings(updatedSettings, for: firstContainerID)

        #expect(store.privacySettings(for: firstContainerID) == updatedSettings)
        #expect(store.privacySettings(for: secondContainerID) == baselineSecondSettings)
    }

    @Test func removingContainerSettingsResetsSpacePrivacyOverrides() {
        let store = SettingsStore.shared
        let containerID = UUID()
        let baselineSettings = store.privacySettings(for: containerID)

        defer {
            store.removeContainerSettings(for: containerID)
        }

        var updatedSettings = baselineSettings
        updatedSettings.cookiesPolicy = baselineSettings.cookiesPolicy == .blockAll ? .allowAll : .blockAll
        updatedSettings.adBlocking.toggle()

        store.setPrivacySettings(updatedSettings, for: containerID)
        #expect(store.privacySettings(for: containerID) == updatedSettings)

        store.removeContainerSettings(for: containerID)
        #expect(store.privacySettings(for: containerID) == baselineSettings)
    }

    @Test func seedsBuiltInAdBlockLists() {
        let builtinIDs = Set(SettingsStore.shared.adBlockFilterLists.filter(\.isBuiltin).map(\.id))

        #expect(builtinIDs.contains(FilterListCatalogService.adGuardBaseID))
        #expect(builtinIDs.contains(FilterListCatalogService.adGuardMobileAdsID))
        #expect(builtinIDs.contains(FilterListCatalogService.adGuardTrackingProtectionID))
        #expect(builtinIDs.contains(FilterListCatalogService.adGuardURLTrackingID))
        #expect(builtinIDs.contains(FilterListCatalogService.adGuardAnnoyancesID))
    }

    @Test func validatesCustomAdBlockURLs() {
        let service = FilterListUpdateService()

        #expect(service.isValidCustomListURL("https://example.com/filter.txt"))
        #expect(service.isValidCustomListURL("http://example.com/filter.txt"))
        #expect(service.isValidCustomListURL("ftp://example.com/filter.txt") == false)
        #expect(service.isValidCustomListURL("file:///tmp/filter.txt") == false)
    }

    @Test func persistsAdBlockUpdateModePerSpace() {
        let store = SettingsStore.shared
        let containerID = UUID()

        defer {
            store.removeContainerSettings(for: containerID)
        }

        var updatedSettings = store.privacySettings(for: containerID)
        updatedSettings.adBlock.updateMode = .aggressiveAuto
        store.setPrivacySettings(updatedSettings, for: containerID)

        #expect(store.privacySettings(for: containerID).adBlock.updateMode == .aggressiveAuto)
    }

    @Test func spacePrivacySettingsDefaultToFingerprintingOnAndCookiesAllowed() {
        let defaults = SpacePrivacySettings()

        #expect(defaults.blockFingerprinting)
        #expect(defaults.cookiesPolicy == .allowAll)
    }

    @Test func fingerprintingEnabledSpacesGenerateProtectionScripts() {
        let disabledScripts = BrowserPrivacyService.privacyScripts(
            for: SpacePrivacySettings(blockFingerprinting: false)
        )
        let enabledScripts = BrowserPrivacyService.privacyScripts(
            for: SpacePrivacySettings(blockFingerprinting: true)
        )

        #expect(disabledScripts.isEmpty)
        #expect(enabledScripts.count == 1)
        #expect(enabledScripts.first?.source.isEmpty == false)
    }

    @Test func fingerprintingScriptDoesNotDependOnCookiePolicy() {
        let allowAllScript = BrowserPrivacyService.privacyScripts(
            for: SpacePrivacySettings(blockFingerprinting: true, cookiesPolicy: .allowAll)
        ).first?.source
        let blockAllScript = BrowserPrivacyService.privacyScripts(
            for: SpacePrivacySettings(blockFingerprinting: true, cookiesPolicy: .blockAll)
        ).first?.source

        #expect(allowAllScript == blockAllScript)
    }

    @Test func balancedFingerprintingProfileIsInternallyCoherent() {
        let profile = FingerprintingProtectionProfile.balanced

        #expect(profile.language == profile.languages.first)
        #expect(profile.availWidth <= profile.screenWidth)
        #expect(profile.availHeight <= profile.screenHeight)
        #expect(profile.devicePixelRatio > 0)
        #expect(profile.platform == "MacIntel")
        #expect(profile.vendor == "Apple Computer, Inc.")
        #expect(profile.mediaDeviceKinds == ["audioinput", "audiooutput", "videoinput"])
    }

    @Test func fingerprintingScriptIncludesBalancedSurfaceNormalization() {
        let script = BrowserPrivacyService.fingerprintingProtectionScriptSource()

        #expect(script.contains("hardwareConcurrency"))
        #expect(script.contains("devicePixelRatio"))
        #expect(script.contains("enumerateDevices"))
        #expect(script.contains("toDataURL"))
        #expect(script.contains("OfflineAudioContext"))
        #expect(script.contains("WebGLRenderingContext"))
    }

    @Test func trackerRegexMatchesRootAndSubdomains() throws {
        let pattern = BrowserPrivacyService.regexForDomain("hotjar.com")
        let regex = try NSRegularExpression(pattern: pattern)
        let rootURL = "https://hotjar.com/script.js"
        let subdomainURL = "https://static.hotjar.com/c/hotjar.js"
        let otherURL = "https://not-hotjar-example.com/script.js"

        let rootRange = NSRange(rootURL.startIndex ..< rootURL.endIndex, in: rootURL)
        let subdomainRange = NSRange(subdomainURL.startIndex ..< subdomainURL.endIndex, in: subdomainURL)
        let otherRange = NSRange(otherURL.startIndex ..< otherURL.endIndex, in: otherURL)

        #expect(regex.firstMatch(in: rootURL, range: rootRange) != nil)
        #expect(regex.firstMatch(in: subdomainURL, range: subdomainRange) != nil)
        #expect(regex.firstMatch(in: otherURL, range: otherRange) == nil)
    }

    @Test func tracksUnsupportedRulesInCoverageSummary() throws {
        let compiler = ContentBlockerCompileService()
        let record = FilterListRecord(
            id: "test-filter",
            name: "Test Filter",
            summary: "Fixture list",
            sourceKind: .custom,
            sourceURL: "https://example.com/filter.txt",
            isRecommended: false,
            enabledByDefault: false
        )

        let rawText = """
        ||ads.example^
        example.com#%#console.log('advanced')
        """

        let artifacts = try compiler.compile(record: record, rawText: rawText)

        #expect(artifacts.coverage.totalRuleCount >= 2)
        #expect(artifacts.coverage.skippedRuleCount >= 1)
        #expect(artifacts.coverage.shardCount >= 1)
        #expect(artifacts.jsonShards.isEmpty == false)
    }

    @Test func artifactIdentifiersSupportDottedListIDs() throws {
        let temporaryArtifactsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ContentBlockerArtifactStore(baseURL: temporaryArtifactsURL)
        let coverage = FilterListCoverage(
            totalRuleCount: 1,
            convertedRuleCount: 1,
            skippedRuleCount: 0,
            safariRuleCount: 1,
            shardCount: 1
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryArtifactsURL)
        }

        try store.storeCompiledArtifacts(
            jsonShards: ["[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"block\"}}]"],
            coverage: coverage,
            for: "custom.list",
            revision: "revision123"
        )

        let identifiers = store.ruleListIdentifiers(for: "custom.list", revision: "revision123")

        #expect(identifiers.count == 1)
        #expect(store.encodedRuleList(for: identifiers[0])?.contains("\"type\":\"block\"") == true)
    }

    @Test func failedAdBlockRefreshPreservesLastKnownGoodRevision() {
        let record = FilterListRecord(
            id: "test-filter",
            name: "Test Filter",
            summary: "Fixture list",
            sourceKind: .custom,
            sourceURL: "https://example.com/filter.txt",
            isRecommended: false,
            enabledByDefault: false,
            status: .ready,
            activeRevision: "last-good-revision",
            coverage: FilterListCoverage(
                totalRuleCount: 10,
                convertedRuleCount: 8,
                skippedRuleCount: 2,
                safariRuleCount: 8,
                shardCount: 1
            )
        )

        let failed = AdBlockService.failedRecord(record, error: AdBlockServiceError.emptyFilterList("Test Filter"))

        #expect(failed.activeRevision == "last-good-revision")
        #expect(failed.status == .failed)
    }

    @Test func settingsRefreshStaysOfflineWithoutCachedRawList() async {
        let store = SettingsStore.shared
        let baselineLists = store.adBlockFilterLists
        let containerID = UUID()
        let temporaryArtifactsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let record = FilterListRecord(
            id: "offline-only-filter",
            name: "Offline Only Filter",
            summary: "Offline refresh regression fixture",
            sourceKind: .custom,
            sourceURL: "https://example.com/filter.txt",
            isRecommended: false,
            enabledByDefault: false,
            status: .ready,
            activeRevision: "existing-revision"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RequestCountingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = AdBlockService(
            updateService: FilterListUpdateService(session: session),
            artifactStore: ContentBlockerArtifactStore(baseURL: temporaryArtifactsURL)
        )

        var settings = store.privacySettings(for: containerID)
        settings.adBlock.enabled = true
        settings.adBlock.updateMode = .manualOnly
        settings.adBlock.enabledBuiltinListIDs = []
        settings.adBlock.enabledCustomListIDs = [record.id]

        RequestCountingURLProtocol.reset()
        store.upsertAdBlockFilterList(record)
        store.setPrivacySettings(settings, for: containerID)

        defer {
            store.setAdBlockFilterLists(baselineLists)
            store.removeContainerSettings(for: containerID)
            try? FileManager.default.removeItem(at: temporaryArtifactsURL)
        }

        let didChange = await service.refreshSpace(containerId: containerID, reason: .settingsChanged)
        let refreshedRecord = store.adBlockFilterList(id: record.id)

        #expect(didChange == false)
        #expect(RequestCountingURLProtocol.requestCount == 0)
        #expect(refreshedRecord?.status == .failed)
        #expect(refreshedRecord?.lastErrorMessage == AdBlockServiceError.missingCachedList(record.name)
            .errorDescription)
        #expect(refreshedRecord?.activeRevision == record.activeRevision)
    }

    @Test @MainActor func tabDisplayTitleReflectsCustomTitleOrFallsBack() {
        let container = TabContainer(name: "Test Space")
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            title: "Original Example Title",
            container: container,
            order: 0
        )

        // Baseline: displayTitle should be the page title
        #expect(tab.displayTitle == "Original Example Title")

        // Set custom title
        tab.customTitle = "My Custom Work Tab"
        #expect(tab.displayTitle == "My Custom Work Tab")

        // Whitespace only custom title falls back to page title
        tab.customTitle = "   "
        #expect(tab.displayTitle == "Original Example Title")

        // Empty custom title falls back to page title
        tab.customTitle = ""
        #expect(tab.displayTitle == "Original Example Title")

        // Fallback when both customTitle and title are empty
        tab.title = ""
        tab.customTitle = nil
        #expect(tab.displayTitle == "New Tab")
    }

    @Test @MainActor func tabResetTitleClearsCustomTitle() {
        let container = TabContainer(name: "Test Space")
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            title: "Original Example Title",
            customTitle: "Renamed Tab",
            container: container,
            order: 0
        )

        #expect(tab.displayTitle == "Renamed Tab")
        tab.resetTitle()
        #expect(tab.customTitle == nil)
        #expect(tab.displayTitle == "Original Example Title")
    }

    @Test @MainActor func createTabForNewWindowInheritsContainerAndSetsActive() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let initialTab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/initial")!,
                historyManager: HistoryManager(modelContainer: container, modelContext: context),
                isPrivate: true
            )
        )
        let initialContainer = initialTab.container
        let initialCount = initialContainer.tabs.count

        let config = WKWebViewConfiguration()
        let targetURL = URL(string: "https://example.com/app/child")!

        let page = tabManager.createTabForNewWindow(
            configuration: config,
            targetURL: targetURL,
            parentTab: initialTab,
            focusAfterOpening: true
        )

        #expect(page != nil)
        let newActiveTab = try #require(tabManager.activeTab)
        #expect(newActiveTab.id != initialTab.id)
        #expect(newActiveTab.url == targetURL)
        #expect(newActiveTab.container.id == initialContainer.id)
        #expect(newActiveTab.isWebViewReady == true)
        #expect(newActiveTab.browserPage != nil)
        #expect(initialContainer.tabs.count == initialCount + 1)
    }

    @Test @MainActor func delegateDidRequestOpenInNewTabOpensTabInsteadOfPeek() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        let downloadManager = DownloadManager(modelContainer: container, modelContext: context)

        let initialTab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/initial")!,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: true
            )
        )

        let delegate = TabBrowserPageDelegate()
        delegate.tab = initialTab

        let targetURL = URL(string: "https://example.com/system/newpage")!
        let dummyPage = BrowserEngine.shared.makePage(
            engineKind: .webkit,
            profile: BrowserEngine.shared.makeProfile(identifier: initialTab.container.id, isPrivate: true),
            configuration: BrowserPageConfiguration.oraDefault(userScripts: [], privacySettings: .init()),
            delegate: nil
        )

        delegate.browserPage(dummyPage, didRequestOpenInNewTab: targetURL)

        #expect(tabManager.peekTab == nil)
        let newlyOpenedTab = tabManager.activeTab
        #expect(newlyOpenedTab?.url == targetURL)
        #expect(newlyOpenedTab?.id != initialTab.id)
    }

    @Test @MainActor func delegateBrowserPageDidCloseClosesTab() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)

        let initialTab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/parent")!,
                historyManager: historyManager,
                isPrivate: true
            )
        )

        let popupTab = try #require(
            tabManager.openTab(
                url: URL(string: "https://example.com/popup")!,
                historyManager: historyManager,
                insertAfter: initialTab,
                isPrivate: true
            )
        )

        #expect(tabManager.activeTab?.id == popupTab.id)

        let delegate = TabBrowserPageDelegate()
        delegate.tab = popupTab

        let dummyPage = BrowserEngine.shared.makePage(
            engineKind: .webkit,
            profile: BrowserEngine.shared.makeProfile(identifier: popupTab.container.id, isPrivate: true),
            configuration: BrowserPageConfiguration.oraDefault(userScripts: [], privacySettings: .init()),
            delegate: nil
        )

        delegate.browserPageDidClose(dummyPage)

        #expect(tabManager.activeTab?.id != popupTab.id)
        #expect(!initialTab.container.tabs.contains(where: { $0.id == popupTab.id }))
    }

    @Test @MainActor func openTabSupportsAboutBlankWithoutHost() throws {
        let container = try ModelConfiguration.createOraContainer(isPrivate: true)
        let context = ModelContext(container)
        let media = MediaController()
        let tabManager = TabManager(modelContainer: container, modelContext: context, mediaController: media)

        let historyManager = HistoryManager(modelContainer: container, modelContext: context)
        let aboutBlankTab = tabManager.openTab(
            url: URL(string: "about:blank")!,
            historyManager: historyManager,
            isPrivate: true
        )

        #expect(aboutBlankTab != nil)
        #expect(aboutBlankTab?.url == URL(string: "about:blank"))
    }

    // MARK: - QA & Developer Mode Tests

    @Test func qaViewportPresetDimensionsAndOrientation() {
        let qaState = QAModeState()

        #expect(qaState.activePreset == .default)
        #expect(qaState.effectiveDimensions == nil)
        #expect(!qaState.isViewportActive)

        qaState.selectPreset(.mobileM)
        #expect(qaState.isViewportActive)
        #expect(qaState.effectiveDimensions?.width == 375)
        #expect(qaState.effectiveDimensions?.height == 667)

        // Toggle to landscape
        qaState.toggleOrientation()
        #expect(qaState.isLandscape)
        #expect(qaState.effectiveDimensions?.width == 667)
        #expect(qaState.effectiveDimensions?.height == 375)

        // Reset to default
        qaState.selectPreset(.default)
        #expect(!qaState.isViewportActive)
        #expect(qaState.effectiveDimensions == nil)
    }

    @Test func qaMultiDeviceGridManagement() {
        let qaState = QAModeState()

        #expect(!qaState.isMultiDeviceActive)
        #expect(qaState.multiDevicePresets.count == 3) // Mobile M, Tablet, Laptop

        qaState.toggleMultiDevice()
        #expect(qaState.isMultiDeviceActive)

        // Add a preset
        qaState.addMultiDevicePreset(.desktop)
        #expect(qaState.multiDevicePresets.contains(.desktop))

        // Remove a preset
        qaState.removeMultiDevicePreset(.desktop)
        #expect(!qaState.multiDevicePresets.contains(.desktop))

        // Toggle off
        qaState.toggleMultiDevice()
        #expect(!qaState.isMultiDeviceActive)
    }

    @Test func qaCookieJSONParsing() throws {
        let jsonString = """
        [
            {
                "name": "session_token",
                "value": "xyz123abc",
                "domain": ".example.com",
                "path": "/",
                "secure": true,
                "httpOnly": true,
                "expirationDate": 1893456000
            },
            {
                "name": "analytics_id",
                "value": "track_99",
                "domain": "sub.otherdomain.org",
                "path": "/dash",
                "secure": false
            }
        ]
        """
        let data = Data(jsonString.utf8)

        // Test with domain filter for "example.com"
        let cookies = try CookieImportService.shared.parseJSONCookies(
            data: data,
            domainFilter: "example.com"
        )
        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "session_token")
        #expect(cookies.first?.value == "xyz123abc")
        #expect(cookies.first?.isSecure == true)

        // Test with no domain filter (all cookies imported)
        let allCookies = try CookieImportService.shared.parseJSONCookies(
            data: data,
            domainFilter: nil
        )
        #expect(allCookies.count == 2)
    }

    @Test func qaDeviceSyncBridgeScriptGeneration() {
        let script = DeviceSyncBridge.injectionScript
        #expect(script.contains("__nfSyncBridgeInstalled"))
        #expect(script.contains("qaSyncEvent"))
        #expect(script.contains("__nfSyncScroll"))
    }

    @Test func qaCrossEngineToggleAndMutualExclusivity() {
        let qaState = QAModeState()

        #expect(!qaState.isCrossEngineActive)
        qaState.toggleCrossEngine()
        #expect(qaState.isCrossEngineActive)
        #expect(qaState.isViewportActive)
        #expect(!qaState.isMultiDeviceActive)
        #expect(qaState.activePreset == .default)

        // Selecting preset turns off cross-engine
        qaState.selectPreset(.tablet)
        #expect(!qaState.isCrossEngineActive)
        #expect(qaState.activePreset == .tablet)

        // Toggling multi-device turns off preset and cross-engine
        qaState.toggleMultiDevice()
        #expect(qaState.isMultiDeviceActive)
        #expect(!qaState.isCrossEngineActive)
    }

    @Test func qaBreakpointScannerScriptIntegrity() {
        let script = BreakpointScanner.extractionScript
        #expect(script.contains("document.styleSheets"))
        #expect(script.contains("min-width"))
        #expect(script.contains("max-width"))
    }

    @Test func qaAccessibilityFilterOptions() {
        #expect(VisionDefectFilter.allCases.count >= 6)
        #expect(ForcedColorScheme.allCases.count == 3)
    }
}


