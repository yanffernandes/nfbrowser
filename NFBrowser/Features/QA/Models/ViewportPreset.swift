import Foundation
import SwiftUI

enum ViewportPreset: String, CaseIterable, Identifiable, Codable {
    case `default` = "Default"
    case mobileS = "Mobile S"
    case mobileM = "Mobile M"
    case mobileL = "Mobile L"
    case tablet = "Tablet"
    case laptop = "Laptop"
    case laptopL = "Laptop L"
    case desktop = "Desktop"
    case custom = "Custom"

    var id: String { rawValue }

    var dimensions: (width: CGFloat, height: CGFloat)? {
        switch self {
        case .default:
            return nil
        case .mobileS:
            return (320, 568)
        case .mobileM:
            return (375, 667)
        case .mobileL:
            return (425, 812)
        case .tablet:
            return (768, 1024)
        case .laptop:
            return (1024, 768)
        case .laptopL:
            return (1440, 900)
        case .desktop:
            return (1920, 1080)
        case .custom:
            return nil
        }
    }

    var label: String {
        switch self {
        case .default:
            return "Default"
        case .mobileS:
            return "Mobile S — 320 × 568"
        case .mobileM:
            return "Mobile M — 375 × 667"
        case .mobileL:
            return "Mobile L — 425 × 812"
        case .tablet:
            return "Tablet — 768 × 1024"
        case .laptop:
            return "Laptop — 1024 × 768"
        case .laptopL:
            return "Laptop L — 1440 × 900"
        case .desktop:
            return "Desktop — 1920 × 1080"
        case .custom:
            return "Custom"
        }
    }

    var shortName: String {
        switch self {
        case .default:
            return "Default"
        case .mobileS:
            return "Mobile S"
        case .mobileM:
            return "Mobile M"
        case .mobileL:
            return "Mobile L"
        case .tablet:
            return "Tablet"
        case .laptop:
            return "Laptop"
        case .laptopL:
            return "Laptop L"
        case .desktop:
            return "Desktop"
        case .custom:
            return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .default:
            return "macwindow"
        case .mobileS, .mobileM, .mobileL:
            return "iphone"
        case .tablet:
            return "ipad"
        case .laptop, .laptopL:
            return "laptopcomputer"
        case .desktop:
            return "display"
        case .custom:
            return "slider.horizontal.3"
        }
    }
}
