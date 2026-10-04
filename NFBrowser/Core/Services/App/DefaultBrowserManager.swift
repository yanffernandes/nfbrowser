//
//  DefaultBrowserManager.swift
//  ora
//
//  Created by keni on 9/30/25.
//

import AppKit
import Combine
import CoreServices

class DefaultBrowserManager: ObservableObject {
    static let shared = DefaultBrowserManager()

    @Published var isDefault: Bool = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        updateIsDefault()
        // Check when app becomes active (e.g. user returning from System Settings)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.updateIsDefault()
            }
            .store(in: &cancellables)

        // Low-frequency fallback check
        Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateIsDefault()
            }
            .store(in: &cancellables)
    }

    private func updateIsDefault() {
        let newValue = Self.checkIsDefault()
        if newValue != isDefault {
            isDefault = newValue
        }
    }

    static func checkIsDefault() -> Bool {
        guard let testURL = URL(string: "http://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: testURL),
              let appBundle = Bundle(url: appURL)
        else {
            return false
        }

        return appBundle.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    static func requestSetAsDefault() {
        let bundleID = Bundle.main.bundleIdentifier! as CFString
        LSSetDefaultHandlerForURLScheme("http" as CFString, bundleID)
        LSSetDefaultHandlerForURLScheme("https" as CFString, bundleID)
    }
}
