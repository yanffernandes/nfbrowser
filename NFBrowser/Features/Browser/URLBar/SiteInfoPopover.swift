import AppKit
import SwiftUI

struct SiteInfoPopover: View {
    let tab: Tab
    @Environment(\.theme) private var theme
    @State private var permissionsReset = false

    private var siteName: String {
        MediaCapturePermissions.siteName(for: tab.url)
    }

    private var isSecure: Bool {
        tab.url.scheme == "https"
    }

    private var isLocalOrInternal: Bool {
        tab.url.scheme == "file" || tab.url.scheme == "about" || tab.url.host == "localhost" || tab.url.host == "127.0.0.1"
    }

    private var allowedDevices: BrowserMediaDevices {
        if permissionsReset { return [] }
        return tab.pageDelegate?.allowedMediaDevices(for: siteName) ?? []
    }

    private var deniedDevices: BrowserMediaDevices {
        if permissionsReset { return [] }
        return tab.pageDelegate?.deniedMediaDevices(for: siteName) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Connection Security
            HStack(spacing: 10) {
                Image(systemName: securityIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(securityColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(securityTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.foreground)

                    Text(siteName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Divider()

            // 2. Rendering Engine
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Engine:")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        Text(tab.container.engineKind.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(tab.container.engineKind == .chromium ? .orange : .blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((tab.container.engineKind == .chromium ? Color.orange : Color.blue).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Text(tab.container.engineKind == .chromium ? "Chromium 154 (Blink & V8 via CEF)" : "WebKit (Safari engine, energy efficient)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // 3. Permissions
            VStack(alignment: .leading, spacing: 8) {
                Text("SITE PERMISSIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                permissionRow(name: "Camera", icon: "video.fill", device: .camera)
                permissionRow(name: "Microphone", icon: "mic.fill", device: .microphone)
                permissionRow(name: "Screen Sharing", icon: "display", device: .screen, askAlways: true)

                if hasCustomPermissions {
                    Button(action: resetPermissions) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Reset Permissions")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }

            Divider()

            // 4. Privacy & Sandbox
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 13))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Protection & Sandbox")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.foreground)

                    Text("Isolated storage in “\(tab.container.name)”. Ad & tracker blocking active.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Helpers

    private var securityIcon: String {
        if isSecure { return "lock.fill" }
        if isLocalOrInternal { return "network" }
        return "exclamationmark.triangle.fill"
    }

    private var securityColor: Color {
        if isSecure { return .green }
        if isLocalOrInternal { return .blue }
        return .orange
    }

    private var securityTitle: String {
        if isSecure { return "Connection is Secure" }
        if isLocalOrInternal { return "Local Page" }
        return "Not Secure"
    }

    private var hasCustomPermissions: Bool {
        !allowedDevices.isEmpty || !deniedDevices.isEmpty
    }

    private func resetPermissions() {
        tab.pageDelegate?.resetMediaPermissions(for: siteName)
        withAnimation {
            permissionsReset = true
        }
    }

    @ViewBuilder
    private func permissionRow(name: String, icon: String, device: BrowserMediaDevices, askAlways: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(name)
                .font(.system(size: 12))
                .foregroundColor(theme.foreground)

            Spacer()

            if askAlways {
                Text("Ask each time")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else if allowedDevices.contains(device) {
                Text("Allowed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.green)
            } else if deniedDevices.contains(device) {
                Text("Blocked")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
            } else {
                Text("Ask (default)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}
