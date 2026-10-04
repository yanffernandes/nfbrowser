import SwiftUI

struct BrowserWebContentView: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var toolbarManager: ToolbarManager
    let tab: Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !toolbarManager.isToolbarHidden {
                URLBar(
                    onSidebarToggle: {
                        NotificationCenter.default.post(
                            name: .toggleSidebar, object: nil
                        )
                    }
                )
                .zIndex(1)
                .transition(
                    .asymmetric(
                        insertion: .push(from: .top),
                        removal: .push(from: .bottom)
                    )
                )
            }

            ZStack {
                webContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if tab.isAgentActive {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.85), Color.blue.opacity(0.65)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .top) {
                        if tab.isAgentActive {
                            AgentActiveIndicatorPill(statusText: tab.agentStatusMessage)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                if appState.isURLBarEditing {
                    Color.black.opacity(0.15)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            DispatchQueue.main.async {
                                appState.isURLBarEditing = false
                            }
                        }
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.isURLBarEditing)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tab.isAgentActive)
    }

    @ViewBuilder
    private var webContent: some View {
        if tab.isWebViewReady {
            if tab.hasNavigationError, let error = tab.navigationError {
                StatusPageView(
                    error: error,
                    failedURL: tab.failedURL,
                    onRetry: { tab.retryNavigation() },
                    onGoBack: tab.canGoBack
                        ? {
                            tab.goBack()
                            tab.clearNavigationError()
                        } : nil,
                    onContinueAnyway: {
                        tab.continueToInsecureSite()
                    }
                )
                .id(tab.id)
            } else if let page = tab.browserPage {
                BrowserPageView(page: page)
                    .overlay(alignment: .topLeading) {
                        if let triggerState = tab.passwordTriggerOverlayState {
                            PasswordAutofillTriggerView(overlay: triggerState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if let passwordOverlayState = tab.passwordOverlayState {
                            PasswordAutofillOverlayView(overlay: passwordOverlayState, tab: tab)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if appState.showFinderIn == tab.id {
                            FindView(page: page)
                                .padding(.top, 16)
                                .padding(.trailing, 16)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if let hovered = tab.hoveredLinkURL, !hovered.isEmpty {
                            LinkPreview(text: hovered)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                ZStack {
                    Rectangle().fill(theme.background)
                    ProgressView().frame(width: 32, height: 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ZStack {
                Rectangle().fill(theme.background)
                ProgressView().frame(width: 32, height: 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct AgentActiveIndicatorPill: View {
    let statusText: String?
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(statusText ?? "Agent active on this tab")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)

            Circle()
                .fill(Color.purple)
                .frame(width: 6, height: 6)
                .opacity(isPulsing ? 1.0 : 0.3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.8), Color.blue.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.purple.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .padding(.top, 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
