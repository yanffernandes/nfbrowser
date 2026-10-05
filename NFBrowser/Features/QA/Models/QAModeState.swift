import Foundation
import SwiftUI

final class QAModeState: ObservableObject {
    @Published var activePreset: ViewportPreset = .default
    @Published var isLandscape: Bool = false
    @Published var customWidth: CGFloat = 375
    @Published var customHeight: CGFloat = 667
    @Published var zoomScale: CGFloat = 1.0
    @Published var isMultiDeviceActive: Bool = false
    @Published var multiDevicePresets: [ViewportPreset] = [.mobileM, .tablet, .laptop]
    @Published var isSyncEnabled: Bool = true
    @Published var isDarkModeForced: Bool? = nil

    var isViewportActive: Bool {
        activePreset != .default || isMultiDeviceActive
    }

    var effectiveDimensions: CGSize? {
        guard let base = activePreset.dimensions ?? (activePreset == .custom ? (customWidth, customHeight) : nil) else {
            return nil
        }
        if isLandscape {
            return CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
        } else {
            return CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        }
    }

    func dimensions(for preset: ViewportPreset, landscape: Bool? = nil) -> CGSize? {
        guard let base = preset.dimensions ?? (preset == .custom ? (customWidth, customHeight) : nil) else {
            return nil
        }
        let applyLandscape = landscape ?? isLandscape
        if applyLandscape {
            return CGSize(width: max(base.width, base.height), height: min(base.width, base.height))
        } else {
            return CGSize(width: min(base.width, base.height), height: max(base.width, base.height))
        }
    }

    func toggleOrientation() {
        isLandscape.toggle()
    }

    func resetToDefault() {
        activePreset = .default
        isMultiDeviceActive = false
        isLandscape = false
        zoomScale = 1.0
    }

    func selectPreset(_ preset: ViewportPreset) {
        if preset == .default {
            resetToDefault()
        } else {
            isMultiDeviceActive = false
            activePreset = preset
        }
    }

    func toggleMultiDevice() {
        isMultiDeviceActive.toggle()
        if isMultiDeviceActive {
            activePreset = .default
        }
    }

    func addMultiDevicePreset(_ preset: ViewportPreset) {
        guard !multiDevicePresets.contains(preset) else { return }
        multiDevicePresets.append(preset)
    }

    func removeMultiDevicePreset(_ preset: ViewportPreset) {
        multiDevicePresets.removeAll { $0 == preset }
        if multiDevicePresets.isEmpty {
            isMultiDeviceActive = false
        }
    }
}
