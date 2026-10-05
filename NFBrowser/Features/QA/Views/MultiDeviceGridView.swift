import AppKit
import SwiftUI

struct MultiDeviceGridView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var qaState: QAModeState
    let onScreenshot: () -> Void

    init(tab: Tab, onScreenshot: @escaping () -> Void) {
        self.tab = tab
        self.qaState = tab.qaState
        self.onScreenshot = onScreenshot
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.08, green: 0.08, blue: 0.10)
                .ignoresSafeArea()

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 28) {
                    ForEach(qaState.multiDevicePresets) { preset in
                        deviceCard(for: preset)
                    }

                    // Add Device Card
                    addDeviceCard
                }
                .padding(.horizontal, 32)
                .padding(.top, 64)
                .padding(.bottom, 32)
            }

            // Top Floating Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 12, weight: .bold))
                    Text("Multi-Device Grid")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)

                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.2))

                // Sync indicator
                Button {
                    qaState.isSyncEnabled.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: qaState.isSyncEnabled ? "link" : "link.badge.plus")
                            .font(.system(size: 11))
                        Text(qaState.isSyncEnabled ? "Sync ON" : "Sync OFF")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(qaState.isSyncEnabled ? Color.green : .white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(qaState.isSyncEnabled ? Color.green.opacity(0.15) : Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Toggle synchronized scroll & click across all devices")

                // Screenshot button
                Button {
                    onScreenshot()
                } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Capture Screenshot")

                Divider()
                    .frame(height: 16)
                    .background(Color.white.opacity(0.2))

                // Exit Multi-Device Grid
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        qaState.isMultiDeviceActive = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Exit Multi-Device Grid")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.92))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            )
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func deviceCard(for preset: ViewportPreset) -> some View {
        if let dims = qaState.dimensions(for: preset) {
            VStack(spacing: 8) {
                // Header strip
                HStack {
                    Image(systemName: preset.iconName)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                    Text(preset.shortName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(Int(dims.width)) × \(Int(dims.height))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    // Remove device from grid
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            qaState.removeMultiDevicePreset(preset)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 10)
                .frame(width: dims.width)

                // Device Frame with Web Content
                ZStack {
                    if let page = tab.browserPage {
                        BrowserPageView(page: page)
                            .frame(width: dims.width, height: dims.height)
                            .background(Color.white)
                    }
                }
                .frame(width: dims.width, height: dims.height)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            }
        }
    }

    private var addDeviceCard: some View {
        Menu {
            ForEach(ViewportPreset.allCases.filter { $0 != .default && !qaState.multiDevicePresets.contains($0) }) { preset in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        qaState.addMultiDevicePreset(preset)
                    }
                } label: {
                    Label(preset.label, systemImage: preset.iconName)
                }
            }
        } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.5))
                Text("Add Viewport")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 180, height: 320)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.1), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            )
        }
        .menuStyle(BorderlessButtonMenuStyle())
    }
}
