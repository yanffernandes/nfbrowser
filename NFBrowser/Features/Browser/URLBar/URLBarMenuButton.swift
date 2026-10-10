import AppKit
import SwiftUI

struct URLBarMenuButton: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var toastManager: ToastManager

    let foregroundColor: Color
    let onShare: (NSView, NSRect) -> Void

    @State private var isHovering = false
    @State private var menuSourceView: NSView?

    private let cornerRadius: CGFloat = 8

    init(foregroundColor: Color, onShare: @escaping (NSView, NSRect) -> Void) {
        self.foregroundColor = foregroundColor
        self.onShare = onShare
    }

    var body: some View {
        Button {
            showMenu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isHovering ? foregroundColor : foregroundColor.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(
                    ConditionallyConcentricRectangle(cornerRadius: cornerRadius)
                        .fill(isHovering ? foregroundColor.opacity(0.12) : Color.clear)
                )
                .clipShape(ConditionallyConcentricRectangle(cornerRadius: cornerRadius))
                .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(TactileBarButtonStyle())
        .onHover { hovering in
            isHovering = hovering
        }
        .background(
            MenuSourceView { nsView in
                menuSourceView = nsView
            }
        )
    }

    private func showMenu() {
        guard let sourceView = menuSourceView else { return }

        let menu = NSMenu()
        let activeTab = tabManager.activeTab

        // 1. Profile / Space info
        if let container = tabManager.activeContainer {
            let profileItem = NSMenuItem(
                title: "\(container.name)",
                action: nil,
                keyEquivalent: ""
            )
            profileItem.state = .on
            profileItem.isEnabled = false
            menu.addItem(profileItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 2. Viewport Size Submenu
        let viewportItem = NSMenuItem(title: "Viewport Size", action: nil, keyEquivalent: "")
        let viewportMenu = NSMenu(title: "Viewport Size")

        for preset in ViewportPreset.allCases {
            let item = NSMenuItem(
                title: preset.label,
                action: #selector(MenuActions.shareAction(_:)),
                keyEquivalent: ""
            )
            if let qa = activeTab?.qaState, qa.activePreset == preset, !qa.isMultiDeviceActive {
                item.state = .on
            }
            let delegate = MenuActions { [weak activeTab] in
                guard let qa = activeTab?.qaState else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    qa.selectPreset(preset)
                }
            }
            item.target = delegate
            item.representedObject = delegate
            viewportMenu.addItem(item)
        }
        viewportItem.submenu = viewportMenu
        menu.addItem(viewportItem)

        // 3. Multi-Device Grid Mode
        let multiDeviceItem = NSMenuItem(
            title: "Multi-Device Grid (QA)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: "Q"
        )
        multiDeviceItem.keyEquivalentModifierMask = [.command, .shift]
        if let qa = activeTab?.qaState, qa.isMultiDeviceActive {
            multiDeviceItem.state = .on
        }
        let multiDeviceDelegate = MenuActions { [weak activeTab] in
            guard let qa = activeTab?.qaState else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                qa.toggleMultiDevice()
            }
        }
        multiDeviceItem.target = multiDeviceDelegate
        multiDeviceItem.representedObject = multiDeviceDelegate
        menu.addItem(multiDeviceItem)

        // 4. Cross-Engine Compare Mode
        let crossEngineItem = NSMenuItem(
            title: "Cross-Engine Compare (WebKit vs Chromium)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: "e"
        )
        crossEngineItem.keyEquivalentModifierMask = [.command, .option]
        if let qa = activeTab?.qaState, qa.isCrossEngineActive {
            crossEngineItem.state = .on
        }
        let crossEngineDelegate = MenuActions { [weak activeTab] in
            guard let qa = activeTab?.qaState else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                qa.toggleCrossEngine()
            }
        }
        crossEngineItem.target = crossEngineDelegate
        crossEngineItem.representedObject = crossEngineDelegate
        menu.addItem(crossEngineItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Import Cookies Submenu
        let importCookiesItem = NSMenuItem(title: "Import Cookies", action: nil, keyEquivalent: "")
        let importCookiesMenu = NSMenu(title: "Import Cookies")

        // From Arc Browser
        let importArcItem = NSMenuItem(
            title: "From Arc Browser (Current Site)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let importArcDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let tab = activeTab else { return }
            let domain = tab.url.host
            Task { @MainActor in
                do {
                    let count = try await CookieImportService.shared.importFromArc(
                        into: tab.container,
                        domainFilter: domain
                    )
                    toastManager?.show("Imported \(count) cookies from Arc", icon: .system("arrow.down.doc.fill"))
                    tab.reload()
                } catch {
                    toastManager?.show("Failed to read Arc cookies: \(error.localizedDescription)", icon: .system("exclamationmark.triangle"))
                }
            }
        }
        importArcItem.target = importArcDelegate
        importArcItem.representedObject = importArcDelegate
        importCookiesMenu.addItem(importArcItem)

        // From Arc Browser (All)
        let importArcAllItem = NSMenuItem(
            title: "From Arc Browser (All Cookies)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let importArcAllDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let tab = activeTab else { return }
            Task { @MainActor in
                do {
                    let count = try await CookieImportService.shared.importFromArc(
                        into: tab.container,
                        domainFilter: nil
                    )
                    toastManager?.show("Imported \(count) total cookies from Arc", icon: .system("arrow.down.doc.fill"))
                    tab.reload()
                } catch {
                    toastManager?.show("Failed to read Arc cookies", icon: .system("exclamationmark.triangle"))
                }
            }
        }
        importArcAllItem.target = importArcAllDelegate
        importArcAllItem.representedObject = importArcAllDelegate
        importCookiesMenu.addItem(importArcAllItem)

        // From Google Chrome (Current Site)
        let importChromeItem = NSMenuItem(
            title: "From Google Chrome (Current Site)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let importChromeDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let tab = activeTab else { return }
            let domain = tab.url.host
            Task { @MainActor in
                do {
                    let count = try await CookieImportService.shared.importFromChrome(
                        into: tab.container,
                        domainFilter: domain
                    )
                    toastManager?.show("Imported \(count) cookies from Chrome", icon: .system("arrow.down.doc.fill"))
                    tab.reload()
                } catch {
                    toastManager?.show("Failed to read Chrome cookies: \(error.localizedDescription)", icon: .system("exclamationmark.triangle"))
                }
            }
        }
        importChromeItem.target = importChromeDelegate
        importChromeItem.representedObject = importChromeDelegate
        importCookiesMenu.addItem(importChromeItem)

        // From Google Chrome (All Cookies)
        let importChromeAllItem = NSMenuItem(
            title: "From Google Chrome (All Cookies)",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let importChromeAllDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let tab = activeTab else { return }
            Task { @MainActor in
                do {
                    let count = try await CookieImportService.shared.importFromChrome(
                        into: tab.container,
                        domainFilter: nil
                    )
                    toastManager?.show("Imported \(count) total cookies from Chrome", icon: .system("arrow.down.doc.fill"))
                    tab.reload()
                } catch {
                    toastManager?.show("Failed to read Chrome cookies", icon: .system("exclamationmark.triangle"))
                }
            }
        }
        importChromeAllItem.target = importChromeAllDelegate
        importChromeAllItem.representedObject = importChromeAllDelegate
        importCookiesMenu.addItem(importChromeAllItem)

        // From JSON File
        let importJSONItem = NSMenuItem(
            title: "From JSON File...",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let importJSONDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let tab = activeTab else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.begin { response in
                guard response == .OK, let fileURL = panel.url, let data = try? Data(contentsOf: fileURL) else { return }
                Task { @MainActor in
                    do {
                        let count = try await CookieImportService.shared.importFromJSON(
                            data: data,
                            into: tab.container,
                            domainFilter: tab.url.host
                        )
                        toastManager?.show("Imported \(count) cookies from JSON", icon: .system("arrow.down.doc.fill"))
                        tab.reload()
                    } catch {
                        toastManager?.show("Invalid cookie JSON file", icon: .system("exclamationmark.triangle"))
                    }
                }
            }
        }
        importJSONItem.target = importJSONDelegate
        importJSONItem.representedObject = importJSONDelegate
        importCookiesMenu.addItem(importJSONItem)

        importCookiesItem.submenu = importCookiesMenu
        menu.addItem(importCookiesItem)

        menu.addItem(NSMenuItem.separator())

        // 5. QA Quick Tools
        let screenshotItem = NSMenuItem(
            title: "Capture Screenshot",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: "S"
        )
        screenshotItem.keyEquivalentModifierMask = [.command, .shift]
        let screenshotDelegate = MenuActions { [weak activeTab, weak toastManager] in
            guard let page = activeTab?.browserPage else { return }
            Task { @MainActor in
                do {
                    let savedURL = try await FullPageScreenshotService.shared.captureScreenshot(
                        from: page,
                        copyToClipboard: true
                    )
                    if savedURL != nil {
                        toastManager?.show("Screenshot saved & copied", icon: .system("camera"))
                    }
                } catch {
                    toastManager?.show("Failed to capture screenshot", icon: .system("exclamationmark.triangle"))
                }
            }
        }
        screenshotItem.target = screenshotDelegate
        screenshotItem.representedObject = screenshotDelegate
        menu.addItem(screenshotItem)

        // 6. Vision Defect Submenu
        let visionItem = NSMenuItem(title: "Emulate Vision Defect", action: nil, keyEquivalent: "")
        let visionMenu = NSMenu(title: "Emulate Vision Defect")
        for filter in VisionDefectFilter.allCases {
            let item = NSMenuItem(
                title: filter.rawValue,
                action: #selector(MenuActions.shareAction(_:)),
                keyEquivalent: ""
            )
            if let qa = activeTab?.qaState, qa.activeVisionFilter == filter {
                item.state = .on
            }
            let delegate = MenuActions { [weak activeTab] in
                guard let tab = activeTab else { return }
                tab.qaState.activeVisionFilter = filter
                if let page = tab.browserPage {
                    AccessibilityFilterService.shared.applyFilter(filter, to: page)
                }
            }
            item.target = delegate
            item.representedObject = delegate
            visionMenu.addItem(item)
        }
        visionItem.submenu = visionMenu
        menu.addItem(visionItem)

        // 7. Force Color Scheme Submenu
        let schemeItem = NSMenuItem(title: "Emulate Color Scheme", action: nil, keyEquivalent: "")
        let schemeMenu = NSMenu(title: "Emulate Color Scheme")
        for scheme in ForcedColorScheme.allCases {
            let item = NSMenuItem(
                title: scheme.rawValue,
                action: #selector(MenuActions.shareAction(_:)),
                keyEquivalent: ""
            )
            if let qa = activeTab?.qaState, qa.forcedColorScheme == scheme {
                item.state = .on
            }
            let delegate = MenuActions { [weak activeTab] in
                guard let tab = activeTab else { return }
                tab.qaState.forcedColorScheme = scheme
                if let page = tab.browserPage {
                    AccessibilityFilterService.shared.applyColorScheme(scheme, to: page)
                }
            }
            item.target = delegate
            item.representedObject = delegate
            schemeMenu.addItem(item)
        }
        schemeItem.submenu = schemeMenu
        menu.addItem(schemeItem)

        menu.addItem(NSMenuItem.separator())

        // 6. Share Link
        let shareItem = NSMenuItem(
            title: "Share Link",
            action: #selector(MenuActions.shareAction(_:)),
            keyEquivalent: ""
        )
        let delegate = MenuActions { [sourceView] in
            let rect = sourceView.bounds
            onShare(sourceView, rect)
        }
        shareItem.target = delegate
        shareItem.representedObject = delegate
        menu.addItem(shareItem)

        let point = NSPoint(x: 0, y: sourceView.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sourceView)
    }
}

private class MenuActions: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func shareAction(_ sender: Any?) {
        handler()
    }
}

private struct MenuSourceView: NSViewRepresentable {
    let onViewCreated: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async {
            onViewCreated(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
