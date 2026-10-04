import SwiftUI

struct EditContainerModal: View {
    let container: TabContainer
    let dismiss: () -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager

    @State private var name: String = ""
    @State private var iconSystemName: String = ""
    @State private var selectedEngine: BrowserEngineKind = .webkit

    var body: some View {
        // Outer frame
        VStack(alignment: .leading, spacing: 0) {
            // Inner content
            VStack(alignment: .leading, spacing: 0) {
                headerView
                containerForm
                Spacer()
                actionButtons
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
        .onAppear { setupInitialValues() }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            OraIcons(icon: .spaceCards, size: .custom(48), color: theme.mutedForeground)
            VStack(alignment: .leading, spacing: 4) {
                Text("Edit Space")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(theme.foreground)
                Text("Update name, icon, and browser engine")
                    .font(.system(size: 13))
                    .foregroundColor(theme.mutedForeground)
            }
        }
        .padding(.bottom, 20)
    }

    private var containerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContainerForm(
                name: $name,
                iconSystemName: $iconSystemName,
                onSubmit: saveContainer
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
        }
    }

    private var actionButtons: some View {
        HStack {
            OraButton(label: "Cancel", variant: .secondary, keyboardShortcut: "esc", action: dismiss)
            Spacer()
            OraButton(label: "Save", isDisabled: name.isEmpty, keyboardShortcut: "return", action: saveContainer)
        }
    }

    private func setupInitialValues() {
        name = container.name
        iconSystemName = container.systemImage
        selectedEngine = container.engineKind
    }

    private func saveContainer() {
        guard !name.isEmpty else { return }

        container.engineKind = selectedEngine
        tabManager.renameContainer(container, name: name, emoji: "", iconSystemName: iconSystemName)
        try? tabManager.modelContext.save()
        dismiss()
    }
}
