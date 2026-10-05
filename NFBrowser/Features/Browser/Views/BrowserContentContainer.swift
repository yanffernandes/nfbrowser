import SwiftUI

struct BrowserContentContainer<Content: View>: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sidebarManager: SidebarManager

    let content: () -> Content

    private var isCompleteFullscreen: Bool {
        appState.isFullscreen && sidebarManager.isSidebarHidden
    }

    private let cornerRadius: CGFloat = 11

    init(
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: isCompleteFullscreen ? 0 : cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: isCompleteFullscreen ? 0 : cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .padding(
                isCompleteFullscreen
                    ? EdgeInsets(
                        top: 0,
                        leading: 0,
                        bottom: 0,
                        trailing: 0
                    )
                    : EdgeInsets(
                        top: 6,
                        leading: sidebarManager.sidebarPosition != .primary || sidebarManager.hiddenSidebar
                            .side == .primary ? 6 : 0,
                        bottom: 6,
                        trailing: sidebarManager.sidebarPosition != .secondary || sidebarManager.hiddenSidebar
                            .side == .secondary ? 6 : 0
                    )
            )
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: appState.isFullscreen)
            .shadow(color: .black.opacity(0.12), radius: isCompleteFullscreen ? 0 : 8, x: 0, y: 2)
            .ignoresSafeArea(.all)
    }
}
