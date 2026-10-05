import Foundation

extension Notification.Name {
    static let toggleSidebar = Notification.Name("ToggleSidebar")
    static let toggleSidebarPosition = Notification.Name("ToggleSidebarPosition")
    static let copyAddressURL = Notification.Name("CopyAddressURL")

    static let showLauncher = Notification.Name("ShowLauncher")
    static let closeActiveTab = Notification.Name("CloseActiveTab")
    static let restoreLastTab = Notification.Name("RestoreLastTab")
    static let tabClosedOrChanged = Notification.Name("TabClosedOrChanged")
    static let findInPage = Notification.Name("FindInPage")
    static let toggleFullURL = Notification.Name("ToggleFullURL")
    static let reloadPage = Notification.Name("ReloadPage")
    static let goBack = Notification.Name("GoBack")
    static let goForward = Notification.Name("GoForward")
    static let togglePinTab = Notification.Name("TogglePinTab")
    static let renameActiveTab = Notification.Name("RenameActiveTab")
    static let nextTab = Notification.Name("NextTab")
    static let previousTab = Notification.Name("PreviousTab")
    static let toggleToolbar = Notification.Name("ToggleToolbar")
    static let toggleAgentTerminal = Notification.Name("ToggleAgentTerminal")
    static let toggleSplitView = Notification.Name("ToggleSplitView")
    static let selectTabAtIndex = Notification.Name("SelectTabAtIndex") // userInfo: ["index": Int]

    // Per-window settings/events
    static let setAppearance = Notification.Name("SetAppearance") // userInfo: ["appearance": String]
    static let checkForUpdates = Notification.Name("CheckForUpdates")

    /// AppDelegate → UI routing
    static let openURL = Notification.Name("OpenURL") // userInfo: ["url": URL]

    // Cache and cookies
    static let clearCacheAndReload = Notification.Name("ClearCacheAndReload")
    static let clearCookiesAndReload = Notification.Name("ClearCookiesAndReload")
    static let spacePrivacySettingsChanged = Notification.Name("SpacePrivacySettingsChanged")
    static let importArcData = Notification.Name("ImportArcData")

    // QA & Developer Mode
    static let toggleResponsiveViewport = Notification.Name("ToggleResponsiveViewport")
    static let toggleMultiDeviceGrid = Notification.Name("ToggleMultiDeviceGrid")
    static let captureQAScreenshot = Notification.Name("CaptureQAScreenshot")

    /// App lifecycle
    static let quitRequested = Notification.Name("QuitRequested")
}
