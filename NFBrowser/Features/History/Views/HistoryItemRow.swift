import AppKit
import SwiftUI

struct HistoryItemRow: View {
    let item: History
    let isSelected: Bool
    let showSpaceBadge: Bool
    let onOpen: () -> Void
    let onOpenNewTab: () -> Void
    let onDelete: () -> Void

    @Environment(\.theme) private var theme
    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(spacing: 12) {
            // Favicon
            AsyncImage(url: item.faviconURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .cornerRadius(3)
                default:
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
            }

            // Title & URL
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? (item.url.host ?? item.urlString) : item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)

                    if item.visitCount > 1 {
                        Text("\(item.visitCount)×")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if showSpaceBadge, let containerName = item.container?.name, !containerName.isEmpty {
                        Text(containerName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(item.urlString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Time
            Text(Self.timeFormatter.string(from: item.lastAccessedAt))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Hover actions
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button(action: onOpenNewTab) {
                        Image(systemName: "plus.rectangle.on.rectangle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open in New Tab")

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.urlString, forType: .string)
                    }) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.85))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete from History")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : (isHovered ? theme.foreground.opacity(0.06) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onOpen()
        }
    }
}
