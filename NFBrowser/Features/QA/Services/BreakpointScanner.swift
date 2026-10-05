import Foundation
import WebKit

final class BreakpointScanner {
    static let shared = BreakpointScanner()

    private init() {}

    static let extractionScript = """
    (function() {
        try {
            const widths = new Set();
            for (let i = 0; i < document.styleSheets.length; i++) {
                try {
                    const sheet = document.styleSheets[i];
                    const rules = sheet.cssRules || sheet.rules;
                    if (!rules) continue;
                    for (let j = 0; j < rules.length; j++) {
                        const rule = rules[j];
                        if (rule.type === 4 && rule.media && rule.media.mediaText) {
                            const mediaText = rule.media.mediaText;
                            const matches = mediaText.match(/(min-width|max-width):\\s*(\\d+)px/g);
                            if (matches) {
                                for (let k = 0; k < matches.length; k++) {
                                    const numMatch = matches[k].match(/(\\d+)/);
                                    if (numMatch && numMatch[1]) {
                                        const px = parseInt(numMatch[1], 10);
                                        if (px >= 320 && px <= 2560) {
                                            widths.add(px);
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch (e) {
                    // Stylesheet is cross-origin, ignore
                }
            }
            return Array.from(widths).sort(function(a, b) { return a - b; });
        } catch (err) {
            return [];
        }
    })();
    """

    @MainActor
    func scanBreakpoints(in webView: WKWebView) async -> [Int] {
        do {
            let result = try await webView.evaluateJavaScript(Self.extractionScript)
            if let numbers = result as? [NSNumber] {
                return numbers.map { $0.intValue }
            }
            return []
        } catch {
            return []
        }
    }
}
