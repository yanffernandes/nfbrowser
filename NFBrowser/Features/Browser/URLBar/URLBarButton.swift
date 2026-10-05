import AppKit
import SwiftUI

struct URLBarButton: View {
    let systemName: String
    let isEnabled: Bool
    let foregroundColor: Color
    let action: () -> Void
    @State private var isHovering = false

    private let cornerRadius: CGFloat = 8

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isEnabled ?
                    (isHovering ? foregroundColor : foregroundColor.opacity(0.75)) :
                    foregroundColor.opacity(0.25)
                )
                .frame(width: 30, height: 30)
                .background(
                    ConditionallyConcentricRectangle(cornerRadius: cornerRadius)
                        .fill(isHovering && isEnabled ? foregroundColor.opacity(0.12) : Color.clear)
                )
                .clipShape(ConditionallyConcentricRectangle(cornerRadius: cornerRadius))
                .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(TactileBarButtonStyle())
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
