import SwiftUI

struct RenameTabModal: View {
    let tab: Tab
    let dismiss: () -> Void

    @Environment(\.theme) private var theme
    @State private var titleText: String = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        // Outer frame
        VStack(alignment: .leading, spacing: 0) {
            // Inner content
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(theme.foreground)
                        .frame(width: 36, height: 36)
                        .background(theme.mutedBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rename Tab")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(theme.foreground)

                        Text("Enter a custom title for this tab, or leave it blank to reset.")
                            .font(.system(size: 12))
                            .foregroundColor(theme.mutedForeground)
                    }
                }
                .padding(.bottom, 16)

                // Input
                OraInput(
                    text: $titleText,
                    placeholder: tab.title.isEmpty ? "New Tab" : tab.title,
                    size: .md,
                    onSubmit: save
                )
                .focused($isFieldFocused)
                .padding(.bottom, 20)

                // Actions
                HStack(spacing: 8) {
                    if tab.customTitle != nil {
                        Button(action: reset) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                Text("Reset to Original")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(theme.mutedForeground)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    OraButton(label: "Cancel", variant: .secondary, keyboardShortcut: "esc", action: dismiss)
                    OraButton(label: "Save", variant: .default, keyboardShortcut: "return", action: save)
                }
            }
            .frame(width: 380)
            .padding(16)
            .background(theme.popoverMutedBackground)
            .cornerRadius(12)
            .overlay {
                ConditionallyConcentricRectangle(cornerRadius: 12)
                    .stroke(theme.border, lineWidth: 0.5)
            }
        }
        .padding(3)
        .background(theme.popoverBackground)
        .cornerRadius(15)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .onAppear {
            titleText = tab.customTitle ?? tab.title
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
    }

    private func save() {
        let trimmed = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        tab.customTitle = trimmed.isEmpty ? nil : trimmed
        try? tab.tabManager?.modelContext.save()
        dismiss()
    }

    private func reset() {
        tab.resetTitle()
        dismiss()
    }
}
