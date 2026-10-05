import AppKit
import SwiftUI

struct QAControlStrip: View {
    @ObservedObject var qaState: QAModeState
    let tab: Tab
    var onScreenshot: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var isScanningBreakpoints = false

    var body: some View {
        HStack(spacing: 10) {
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
                HStack(spacing: 5) {
                    Image(systemName: qaState.activePreset.iconName)
                        .font(.system(size: 11, weight: .medium))
                    Text(qaState.activePreset.shortName)
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .opacity(0.6)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
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

            // Discovered Breakpoint pills (if any)
            if !qaState.discoveredBreakpoints.isEmpty {
                HStack(spacing: 4) {
                    ForEach(qaState.discoveredBreakpoints.prefix(4), id: \.self) { bp in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                qaState.customWidth = CGFloat(bp)
                                qaState.selectPreset(.custom)
                            }
                        } label: {
                            Text("\(bp)px")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(qaState.activePreset == .custom && Int(qaState.customWidth) == bp ? Color.accentColor : .white.opacity(0.6))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Jump to site CSS breakpoint \(bp)px")
                    }
                }
            }

            Divider()
                .frame(height: 14)
                .background(Color.white.opacity(0.2))

            // Rotate Orientation
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    qaState.toggleOrientation()
                }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(qaState.isLandscape ? Color.accentColor : .white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Rotate orientation (Portrait / Landscape)")

            // Scan CSS Breakpoints
            Button {
                guard let webView = tab.browserPage?.rawWebView else { return }
                isScanningBreakpoints = true
                Task { @MainActor in
                    let points = await BreakpointScanner.shared.scanBreakpoints(in: webView)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        qaState.discoveredBreakpoints = points
                        isScanningBreakpoints = false
                    }
                }
            } label: {
                Image(systemName: "ruler")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isScanningBreakpoints ? Color.accentColor : .white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Scan page CSS for responsive breakpoints")

            // a11y Vision Defect Filter Menu
            Menu {
                ForEach(VisionDefectFilter.allCases) { filter in
                    Button {
                        qaState.activeVisionFilter = filter
                        if let webView = tab.browserPage?.rawWebView {
                            AccessibilityFilterService.shared.applyFilter(filter, to: webView)
                        }
                    } label: {
                        HStack {
                            if qaState.activeVisionFilter == filter {
                                Image(systemName: "checkmark")
                            }
                            Text(filter.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: qaState.activeVisionFilter == .none ? "eye" : "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(qaState.activeVisionFilter == .none ? .white.opacity(0.85) : Color.yellow)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .help("Vision defect simulation (Protanopia, Deuteranopia, Tritanopia, Monochrome)")

            // Forced Color Scheme Menu (Dark / Light)
            Menu {
                ForEach(ForcedColorScheme.allCases) { scheme in
                    Button {
                        qaState.forcedColorScheme = scheme
                        if let webView = tab.browserPage?.rawWebView {
                            AccessibilityFilterService.shared.applyColorScheme(scheme, to: webView)
                        }
                    } label: {
                        HStack {
                            if qaState.forcedColorScheme == scheme {
                                Image(systemName: "checkmark")
                            }
                            Text(scheme.rawValue)
                        }
                    }
                }
            } label: {
                Image(systemName: qaState.forcedColorScheme.iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(qaState.forcedColorScheme == .system ? .white.opacity(0.85) : Color.accentColor)
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .help("Emulate Dark Mode / Light Mode")

            // Multi-Device Grid Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    qaState.toggleMultiDevice()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 11, weight: .medium))
                    Text("Grid")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(qaState.isMultiDeviceActive ? Color.accentColor : .white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(qaState.isMultiDeviceActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Mirrored Multi-Device Grid")

            // Cross-Engine Compare Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    qaState.toggleCrossEngine()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                    Text("Compare")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(qaState.isCrossEngineActive ? Color.accentColor : .white.opacity(0.85))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(qaState.isCrossEngineActive ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())
            .help("Toggle Cross-Engine Compare Mode (WebKit vs Chromium)")

            // Screenshot Button
            Button {
                onScreenshot?()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Capture Full Page Screenshot")

            Divider()
                .frame(height: 14)
                .background(Color.white.opacity(0.2))

            // Close / Reset Button
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    qaState.resetToDefault()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Reset to Default Viewport (Full Window)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.95))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 14, y: 7)
        )
    }
}
