import SwiftUI

struct BrowserSplitView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var toolbarManager: ToolbarManager
    @EnvironmentObject var sidebarManager: SidebarManager
    @EnvironmentObject var toastManager: ToastManager
    @EnvironmentObject private var browserAgentTerminal: BrowserAgentTerminalManager

    private var targetSide: SplitSide {
        sidebarManager.sidebarPosition == .primary ? .primary : .secondary
    }

    private var splitFraction: FractionHolder {
        sidebarManager.sidebarPosition == .primary
            ? sidebarManager.currentFraction
            : sidebarManager.currentFraction.inverted()
    }

    private var minPF: CGFloat {
        sidebarManager.sidebarPosition == .primary ? 0.10 : 0.7
    }

    private var minSF: CGFloat {
        sidebarManager.sidebarPosition == .primary ? 0.7 : 0.10
    }

    private var prioritySide: SplitSide {
        sidebarManager.sidebarPosition == .primary ? .primary : .secondary
    }

    private var dragToHidePFlag: Bool {
        sidebarManager.sidebarPosition == .primary
    }

    private var dragToHideSFlag: Bool {
        sidebarManager.sidebarPosition == .secondary
    }

    var body: some View {
        HSplit(left: { primaryPane() }, right: { secondaryPane() })
            .hide(sidebarManager.hiddenSidebar)
            .splitter { Splitter.invisible() }
            .fraction(splitFraction)
            .constraints(
                minPFraction: minPF,
                minSFraction: minSF,
                priority: prioritySide,
                dragToHideP: dragToHidePFlag,
                dragToHideS: dragToHideSFlag
            )
            .styling(hideSplitter: true)
    }

    private func primaryPane() -> some View {
        paneContent(
            isSidebarPane: sidebarManager.sidebarPosition == .primary,
            isOtherPaneHidden: sidebarManager.hiddenSidebar.side == .secondary
        )
    }

    private func secondaryPane() -> some View {
        paneContent(
            isSidebarPane: sidebarManager.sidebarPosition == .secondary,
            isOtherPaneHidden: sidebarManager.hiddenSidebar.side == .primary
        )
    }

    @ViewBuilder
    private func paneContent(isSidebarPane: Bool, isOtherPaneHidden: Bool) -> some View {
        if isSidebarPane, !isOtherPaneHidden {
            SidebarView()
        } else {
            contentView()
        }
    }

    private func contentView() -> some View {
        Group {
            if browserAgentTerminal.isPanelVisible {
                HSplit(
                    left: {
                        BrowserContentContainer {
                            if let activeTab = tabManager.activeTab {
                                BrowserTabSplitContainer(activeTab: activeTab)
                            } else {
                                HomeView()
                            }
                        }
                    },
                    right: {
                        BrowserAgentTerminalPanel()
                    }
                )
                .fraction(browserAgentTerminal.contentFraction)
                .splitter {
                    AgentPanelSplitter()
                }
                .constraints(minPFraction: 0.30, minSFraction: 0.10, priority: .primary)
                .styling(visibleThickness: 1)
            } else if let activeTab = tabManager.activeTab {
                BrowserContentContainer {
                    BrowserTabSplitContainer(activeTab: activeTab)
                }
            } else {
                BrowserContentContainer {
                    HomeView()
                }
            }
        }
        .toast(manager: toastManager)
    }
}

@MainActor
private struct AgentPanelSplitter: SplitDivider {
    public var styling: SplitStyling
    @State private var isHovering = false
    @State private var isCursorPushed = false

    init() {
        self.styling = SplitStyling(color: .clear, inset: 0, visibleThickness: 1, invisibleThickness: 14)
    }

    init(styling: SplitStyling) {
        self.styling = styling
    }

    var body: some View {
        ZStack {
            // Invisible wider hit area for easy grabbing
            Color.clear
                .frame(width: 14)

            // Refined, subtle white divider line that brightens on hover
            Rectangle()
                .fill(isHovering ? Color.white.opacity(0.40) : Color.white.opacity(0.12))
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering && !isCursorPushed {
                NSCursor.resizeLeftRight.push()
                isCursorPushed = true
            } else if !hovering && isCursorPushed {
                NSCursor.pop()
                isCursorPushed = false
            }
        }
        .onDisappear {
            if isCursorPushed {
                NSCursor.pop()
                isCursorPushed = false
            }
        }
    }
}
