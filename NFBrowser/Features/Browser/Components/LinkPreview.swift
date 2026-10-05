import SwiftUI

struct LinkPreview: View {
    let text: String
    @Environment(\.theme) private var theme

    private func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "NF Browser \(version)"
    }

    var body: some View {
        VStack {
            Spacer()
            HStack {
                ZStack {
                    Text(text)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(theme.invertedSolidWindowBackgroundColor.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                )

                Spacer()

                Text(getAppVersion())
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.2))
                    )
                    .padding(.trailing, 12)
            }
            .padding(.bottom, 8)
            .padding(.leading, 8)
        }
        .transition(.opacity)
        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: text)
        .allowsHitTesting(false)
        .zIndex(900)
    }
}
