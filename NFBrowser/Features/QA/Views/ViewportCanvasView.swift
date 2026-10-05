import AppKit
import SwiftUI

struct ViewportCanvasView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var qaState: QAModeState
    let onScreenshot: () -> Void

    init(tab: Tab, qaState: QAModeState? = nil, onScreenshot: @escaping () -> Void) {
        self.tab = tab
        self.qaState = qaState ?? tab.qaState
        self.onScreenshot = onScreenshot
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Workspace dark canvas background
                Color(red: 0.09, green: 0.09, blue: 0.11)
                    .ignoresSafeArea()

                // Center device container or full window
                if let dims = qaState.effectiveDimensions, let page = tab.browserPage {
                    let availableHeight = max(geometry.size.height - 100, 200)
                    let availableWidth = max(geometry.size.width - 40, 200)
                    let scaleH = dims.height > availableHeight ? availableHeight / dims.height : 1.0
                    let scaleW = dims.width > availableWidth ? availableWidth / dims.width : 1.0
                    let effectiveScale = min(scaleH, scaleW, 1.0) * qaState.zoomScale

                    VStack(spacing: 8) {
                        Spacer(minLength: 54)

                        // Device Bezel Frame
                        VStack(spacing: 0) {
                            // Subtle Device Header Bar
                            HStack {
                                Circle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 8, height: 8)
                                Spacer()
                                Text(qaState.activePreset.shortName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                Spacer()
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 8, height: 8)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 22)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.17))

                            // Actual Web View
                            BrowserPageView(page: page)
                                .frame(width: dims.width, height: dims.height)
                                .background(Color.white)
                        }
                        .frame(width: dims.width)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 28, x: 0, y: 14)
                        .scaleEffect(effectiveScale)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: dims)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: effectiveScale)

                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let page = tab.browserPage {
                    // Default Viewport (Full Window live browsing)
                    BrowserPageView(page: page)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Floating Control Strip docked at top
                QAControlStrip(qaState: qaState, tab: tab, onScreenshot: onScreenshot)
                    .padding(.top, 12)
            }
        }
    }
}
