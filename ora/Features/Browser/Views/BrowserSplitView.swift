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
        sidebarManager.sidebarPosition == .primary ? 0.16 : 0.7
    }

    private var minSF: CGFloat {
        sidebarManager.sidebarPosition == .primary ? 0.7 : 0.16
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
                                BrowserWebContentView(tab: activeTab)
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
                .constraints(minPFraction: 0.42, minSFraction: 0.24, priority: .primary)
                .styling(visibleThickness: 1)
            } else if let activeTab = tabManager.activeTab {
                BrowserContentContainer {
                    BrowserWebContentView(tab: activeTab)
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
