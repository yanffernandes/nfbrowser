import Foundation

enum VisionDefectFilter: String, CaseIterable, Identifiable {
    case none = "Normal"
    case protanopia = "Protanopia (Red-Blind)"
    case deuteranopia = "Deuteranopia (Green-Blind)"
    case tritanopia = "Tritanopia (Blue-Blind)"
    case achromatopsia = "Achromatopsia (Monochrome)"
    case blurred = "Low Vision (Blur)"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .none: return "Normal"
        case .protanopia: return "Protanopia"
        case .deuteranopia: return "Deuteranopia"
        case .tritanopia: return "Tritanopia"
        case .achromatopsia: return "Monochrome"
        case .blurred: return "Low Vision"
        }
    }
}

enum ForcedColorScheme: String, CaseIterable, Identifiable {
    case system = "System Theme"
    case dark = "Force Dark Mode"
    case light = "Force Light Mode"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

final class AccessibilityFilterService {
    static let shared = AccessibilityFilterService()

    private init() {}

    @MainActor
    func applyFilter(_ filter: VisionDefectFilter, to page: BrowserPage) {
        let cssFilter: String = switch filter {
        case .none:
            "none"
        case .protanopia:
            "url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\"><filter id=\"f\"><feColorMatrix type=\"matrix\" values=\"0.567,0.433,0,0,0 0.558,0.442,0,0,0 0,0.242,0.758,0,0 0,0,0,1,0\"/></filter></svg>#f')"
        case .deuteranopia:
            "url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\"><filter id=\"f\"><feColorMatrix type=\"matrix\" values=\"0.625,0.375,0,0,0 0.7,0.3,0,0,0 0,0.3,0.7,0,0 0,0,0,1,0\"/></filter></svg>#f')"
        case .tritanopia:
            "url('data:image/svg+xml;utf8,<svg xmlns=\"http://www.w3.org/2000/svg\"><filter id=\"f\"><feColorMatrix type=\"matrix\" values=\"0.95,0.05,0,0,0 0,0.433,0.567,0,0 0,0.475,0.525,0,0 0,0,0,1,0\"/></filter></svg>#f')"
        case .achromatopsia:
            "grayscale(100%)"
        case .blurred:
            "blur(2.5px)"
        }

        let js = "document.documentElement.style.filter = \(cssFilter == "none" ? "''" : "'\(cssFilter)'");"
        page.evaluateJavaScript(js)
    }

    @MainActor
    func applyColorScheme(_ scheme: ForcedColorScheme, to page: BrowserPage) {
        let js: String = switch scheme {
        case .system:
            """
            (function() {
                const el = document.getElementById('__nf_forced_color_scheme');
                if (el) el.remove();
                document.documentElement.removeAttribute('data-theme');
            })();
            """
        case .dark:
            """
            (function() {
                let el = document.getElementById('__nf_forced_color_scheme');
                if (!el) {
                    el = document.createElement('style');
                    el.id = '__nf_forced_color_scheme';
                    document.head.appendChild(el);
                }
                el.textContent = '@media (prefers-color-scheme: light) { html { filter: invert(1) hue-rotate(180deg) !important; } img, video, canvas { filter: invert(1) hue-rotate(180deg) !important; } }';
                document.documentElement.setAttribute('data-theme', 'dark');
            })();
            """
        case .light:
            """
            (function() {
                let el = document.getElementById('__nf_forced_color_scheme');
                if (!el) {
                    el = document.createElement('style');
                    el.id = '__nf_forced_color_scheme';
                    document.head.appendChild(el);
                }
                el.textContent = '@media (prefers-color-scheme: dark) { html { filter: invert(1) hue-rotate(180deg) !important; } img, video, canvas { filter: invert(1) hue-rotate(180deg) !important; } }';
                document.documentElement.setAttribute('data-theme', 'light');
            })();
            """
        }
        page.evaluateJavaScript(js)
    }
}
