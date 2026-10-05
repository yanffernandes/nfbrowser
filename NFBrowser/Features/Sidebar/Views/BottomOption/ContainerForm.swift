import SwiftUI

struct ContainerForm: View {
    @Binding var name: String
    @Binding var iconSystemName: String

    let onSubmit: () -> Void

    @Environment(\.theme) private var theme
    @FocusState private var isNameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            iconButton
            nameTextField
        }
        .onAppear { isNameFocused = true }
    }

    private var iconButton: some View {
        Menu {
            ForEach(SpaceIcon.groups) { group in
                Section(group.title) {
                    ForEach(group.icons) { option in
                        Button {
                            iconSystemName = option.name
                        } label: {
                            HStack {
                                Label(option.label, systemImage: option.name)
                                if selectedIcon == option.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.mutedForeground)
                .frame(width: ContainerConstants.UI.emojiButtonSize, height: ContainerConstants.UI.emojiButtonSize)
                .background(
                    theme.mutedBackground,
                    in: RoundedRectangle(cornerRadius: ContainerConstants.UI.cornerRadius)
                )
        }
        .buttonStyle(TactileBarButtonStyle())
        .help("Choose space icon")
        .accessibilityLabel("Choose space icon")
        .menuStyle(.borderlessButton)
    }

    private var selectedIcon: String {
        if SpaceIcon.options.contains(where: { $0.name == iconSystemName }) {
            return iconSystemName
        }
        let mappedIcon = SpaceIcon.systemImage(for: name)
        return SpaceIcon.options.contains(where: { $0.name == mappedIcon }) ? mappedIcon : "square.grid.2x2.fill"
    }

    private var nameTextField: some View {
        OraInput(
            text: $name,
            placeholder: "eg. work, streaming, finance...",
            onSubmit: onSubmit
        )
        .focused($isNameFocused)
    }
}
