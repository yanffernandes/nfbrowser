import AppKit
import SwiftUI

struct NewContainerButton: View {
    @State private var isHovering = false

    @Environment(\.theme) private var theme
    @EnvironmentObject var dialogManager: DialogManager
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        Button(action: {
            dialogManager.show { id in
                NewContainerDialog(dismiss: { dialogManager.dismiss(id: id) })
                    .environmentObject(tabManager)
            }
        }) {
            HStack {
                Image(systemName: "plus")
                    .frame(width: 12, height: 12)
                    .foregroundColor(isHovering ? theme.foreground : .secondary)
            }
            .padding(8)
            .background(isHovering ? theme.invertedSolidWindowBackgroundColor.opacity(0.12) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(TactileBarButtonStyle())
        .onHover { isHovering = $0 }
    }
}

private struct NewContainerDialog: View {
    let dismiss: () -> Void

    @State private var name = ""
    @State private var iconSystemName = ""
    @State private var selectedEngine: BrowserEngineKind = .webkit

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        // Outer frame
        VStack(alignment: .leading, spacing: 0) {
            // Inner content
            VStack(alignment: .leading, spacing: 14) {
                // Icon
                OraIcons(icon: .spaceCards, size: .custom(36), color: theme.mutedForeground)

                // Title
                Text("Create a new Space")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.foreground)

                // Form section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a name")
                        .font(.system(size: 13))
                        .foregroundColor(theme.mutedForeground)

                    ContainerForm(
                        name: $name,
                        iconSystemName: $iconSystemName,
                        onSubmit: createContainer
                    )

                    // Engine Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Browser Engine")
                            .font(.system(size: 13))
                            .foregroundColor(theme.mutedForeground)

                        HStack(spacing: 8) {
                            ForEach(BrowserEngineKind.allCases) { engine in
                                EngineOptionButton(
                                    engine: engine,
                                    isSelected: selectedEngine == engine,
                                    action: { selectedEngine = engine }
                                )
                            }
                        }

                        Text(selectedEngine.shortDescription)
                            .font(.system(size: 11))
                            .foregroundColor(theme.mutedForeground.opacity(0.85))
                    }
                    .padding(.top, 4)

                    // Info text
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("Spaces are isolated profiles with their own history, logins, and engine data.")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(theme.mutedForeground)
                    .padding(.top, 4)
                }

                Spacer()

                // Buttons
                HStack {
                    OraButton(label: "Cancel", variant: .secondary, keyboardShortcut: "esc", action: dismiss)
                    Spacer()
                    OraButton(
                        label: "Save",
                        isDisabled: name.isEmpty,
                        keyboardShortcut: "return",
                        action: createContainer
                    )
                }
            }
            .frame(
                width: ContainerConstants.UI.newContainerDialogWidth,
                height: ContainerConstants.UI.newContainerDialogHeight
            )
            .padding(12)
            .background(theme.popoverMutedBackground)
            .cornerRadius(11)
            .overlay {
                ConditionallyConcentricRectangle(cornerRadius: 11)
                    .stroke(theme.border, lineWidth: 0.5)
            }
        }
        .padding(3)
        .background(theme.popoverBackground)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
    }

    private func createContainer() {
        guard !name.isEmpty else { return }
        tabManager.createContainer(
            name: name,
            emoji: "",
            iconSystemName: iconSystemName,
            engine: selectedEngine
        )
        dismiss()
    }
}

struct EngineOptionButton: View {
    let engine: BrowserEngineKind
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: engine.iconSystemName)
                    .font(.system(size: 12, weight: .medium))
                Text(engine.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .cornerRadius(7)
            .overlay(borderOverlay)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(TactileCardButtonStyle())
    }

    private var backgroundColor: Color {
        isSelected ? theme.accent.opacity(0.18) : theme.mutedBackground.opacity(0.6)
    }

    private var foregroundColor: Color {
        isSelected ? theme.accent : theme.foreground
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(
                isSelected ? theme.accent : theme.border.opacity(0.5),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}
