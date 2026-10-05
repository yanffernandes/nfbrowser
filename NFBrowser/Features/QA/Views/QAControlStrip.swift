import AppKit
import SwiftUI

struct QAControlStrip: View {
    @ObservedObject var qaState: QAModeState
    let tab: Tab
    var onScreenshot: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Preset Picker Menu
            Menu {
                ForEach(ViewportPreset.allCases) { preset in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            qaState.selectPreset(preset)
                        }
                    } label: {
                        HStack {
                            if qaState.activePreset == preset {
                                Image(systemName: "checkmark")
                            }
                            Text(preset.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: qaState.activePreset.iconName)
                        .font(.system(size: 12, weight: .medium))
                    Text(qaState.activePreset.shortName)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9))
                        .opacity(0.6)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
            .menuStyle(BorderlessButtonMenuStyle())

            // Dimensions badge
            if let dims = qaState.effectiveDimensions {
                Text("\(Int(dims.width)) × \(Int(dims.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
            }

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Rotate Orientation
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    qaState.toggleOrientation()
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(qaState.isLandscape ? Color.accentColor : .white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Rotate orientation (Portrait / Landscape)")

            // Multi-Device Grid Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    qaState.toggleMultiDevice()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 12, weight: .medium))
                    Text("Grid")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(qaState.isMultiDeviceActive ? Color.accentColor : .white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(qaState.isMultiDeviceActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Mirrored Multi-Device View")

            // Screenshot Button
            Button {
                onScreenshot?()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Capture Full Page Screenshot")

            Divider()
                .frame(height: 16)
                .background(Color.white.opacity(0.2))

            // Close / Reset Button
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    qaState.resetToDefault()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset to Default Viewport (Full Window)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.92))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
        )
    }
}
