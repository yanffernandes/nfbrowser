import Foundation
import SwiftUI

final class QAModeState: ObservableObject {
    @Published var isQAActive: Bool = false
    @Published var activePreset: ViewportPreset = .default
    @Published var isLandscape: Bool = false
    @Published var customWidth: CGFloat = 375
    @Published var customHeight: CGFloat = 667
    @Published var zoomScale: CGFloat = 1.0
    @Published var gridScale: CGFloat = 0.75
    @Published var isMultiDeviceActive: Bool = false
    @Published var isCrossEngineActive: Bool = false
    @Published var multiDevicePresets: [ViewportPreset] = [.mobileM, .tablet, .laptop]
    @Published var isSyncEnabled: Bool = true {
        didSet {
            DeviceSyncBridge.shared.isEnabled = isSyncEnabled
        }
    }
    @Published var activeVisionFilter: VisionDefectFilter = .none
    @Published var forcedColorScheme: ForcedColorScheme = .system
    @Published var discoveredBreakpoints: [Int] = []

    var isViewportActive: Bool {
        isQAActive || activePreset != .default || isMultiDeviceActive || isCrossEngineActive
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
        isQAActive = false
        activePreset = .default
        isMultiDeviceActive = false
        isCrossEngineActive = false
        isLandscape = false
        zoomScale = 1.0
        activeVisionFilter = .none
        forcedColorScheme = .system
    }

    func selectPreset(_ preset: ViewportPreset) {
        if preset == .default {
            resetToDefault()
        } else {
            isQAActive = true
            isMultiDeviceActive = false
            isCrossEngineActive = false
            activePreset = preset
            if preset != .custom, let d = preset.dimensions {
                customWidth = d.width
                customHeight = d.height
            }
        }
    }

    func toggleMultiDevice() {
        isMultiDeviceActive.toggle()
        if isMultiDeviceActive {
            isQAActive = true
            isCrossEngineActive = false
        }
    }

    func toggleCrossEngine() {
        isCrossEngineActive.toggle()
        if isCrossEngineActive {
            isQAActive = true
            isMultiDeviceActive = false
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
