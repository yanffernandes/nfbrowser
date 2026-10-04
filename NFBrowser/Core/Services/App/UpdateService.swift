import SwiftUI

/// NF Browser will publish its own update channel after the first release.
/// Keep the service inert so this fork can never install upstream Ora builds.
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published var canCheckForUpdates = false
    @Published var updateProgress: Double = 0
    @Published var isCheckingForUpdates = false
    @Published var updateAvailable = false
    @Published var lastCheckResult: String?
    @Published var lastCheckDate: Date?

    func checkForUpdates() {}

    func checkForUpdatesInBackground() {}
}
