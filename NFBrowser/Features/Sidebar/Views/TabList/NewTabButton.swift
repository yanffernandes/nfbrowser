import SwiftUI

struct NewTabButton: View {
    let addNewTab: () -> Void

    @State private var isHovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: addNewTab) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .frame(width: 12, height: 12)

                Text("New Tab")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isHovering ? theme.foreground : .secondary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? theme.activeTabBackground.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(ConditionallyConcentricRectangle(cornerRadius: 10))
            .animation(.easeInOut(duration: 0.14), value: isHovering)
            .geometryGroup()
        }
        .buttonStyle(TactileBarButtonStyle())
        .onHover { isHovering = $0 }
    }
}
