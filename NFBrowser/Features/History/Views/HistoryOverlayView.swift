import AppKit
import SwiftData
import SwiftUI

struct HistoryOverlayView: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var historyManager: HistoryManager
    @EnvironmentObject private var tabManager: TabManager
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var privacyMode: PrivacyMode

    @Query private var rawContainers: [TabContainer]

    private var containers: [TabContainer] {
        rawContainers.sorted(by: TabContainer.stableSort)
    }

    @State private var searchText: String = ""
    @State private var selectedContainerId: UUID? = nil
    @State private var selectedItemId: UUID?
    @State private var showClearConfirmation = false
    @State private var clearOption: ClearOption = .all

    init() {}

    enum ClearOption {
        case currentSpace
        case all
    }

    private var filteredItems: [History] {
        _ = historyManager.historyRevision
        return historyManager.searchAll(searchText, containerId: selectedContainerId)
    }

    private var groupedItems: [(group: HistoryDateGroup, items: [History])] {
        let items = filteredItems
        var grouped: [HistoryDateGroup: [History]] = [:]
        for item in items {
            let group = HistoryDateGroup.group(for: item.lastAccessedAt)
            grouped[group, default: []].append(item)
        }
        return HistoryDateGroup.allCases.compactMap { group in
            if let list = grouped[group], !list.isEmpty {
                return (group, list)
            }
            return nil
        }
    }

    var body: some View {
        ZStack {
            // Dismiss background
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture {
                    close()
                }

            // Modal card
            VStack(spacing: 0) {
                // Header
                headerView

                Divider()

                // Search & Filter Toolbar
                toolbarView

                Divider()

                // Content
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    historyListView
                }

                Divider()

                // Footer
                footerView
            }
            .frame(width: 680, height: 520)
            .background(theme.popoverBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.foreground.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            selectedContainerId = tabManager.activeContainer?.id
        }
        .confirmationDialog(
            "Clear Browsing History",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            if let container = tabManager.activeContainer, selectedContainerId != nil {
                Button("Clear History for “\(container.name)”", role: .destructive) {
                    historyManager.clearContainerHistory(container)
                }
            }
            Button("Clear All Browsing History", role: .destructive) {
                historyManager.clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove visited page records from your browsing history.")
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)

            Text("Browsing History")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(theme.foreground)

            Spacer()

            if !filteredItems.isEmpty {
                Button(action: { showClearConfirmation = true }) {
                    Text("Clear...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(theme.foreground.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search history by title or URL...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.foreground.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Space picker
            Picker("Space", selection: $selectedContainerId) {
                Text("All Spaces").tag(UUID?.none)
                ForEach(containers) { container in
                    Text(container.name).tag(UUID?.some(container.id))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 38))
                .foregroundColor(.secondary.opacity(0.6))

            Text(searchText.isEmpty ? "No history yet" : "No results for “\(searchText)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.foreground)

            Text(searchText.isEmpty ? "Pages you visit will appear here." : "Try searching with different keywords.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groupedItems, id: \.group.id) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.group.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        ForEach(section.items) { item in
                            HistoryItemRow(
                                item: item,
                                isSelected: selectedItemId == item.id,
                                showSpaceBadge: selectedContainerId == nil,
                                onOpen: {
                                    open(item: item, inNewTab: false)
                                },
                                onOpenNewTab: {
                                    open(item: item, inNewTab: true)
                                },
                                onDelete: {
                                    historyManager.deleteItem(item)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var footerView: some View {
        HStack {
            Text("\(filteredItems.count) \(filteredItems.count == 1 ? "entry" : "entries")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            Text("Press Esc to close")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.foreground.opacity(0.02))
    }

    // MARK: - Actions

    private func close() {
        appState.showHistory = false
    }

    private func open(item: History, inNewTab: Bool) {
        close()
        if inNewTab {
            tabManager.openTab(
                url: item.url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: privacyMode.isPrivate
            )
        } else if let activeTab = tabManager.activeTab {
            activeTab.loadURL(item.urlString)
        } else {
            tabManager.openTab(
                url: item.url,
                historyManager: historyManager,
                downloadManager: downloadManager,
                isPrivate: privacyMode.isPrivate
            )
        }
    }
}
