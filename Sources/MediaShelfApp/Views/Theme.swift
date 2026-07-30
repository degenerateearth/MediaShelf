import SwiftUI

enum ShelfTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.055)
    static let elevated = Color(red: 0.075, green: 0.09, blue: 0.12)
    static let accent = Color(red: 0.20, green: 0.78, blue: 0.72)
    static let secondaryAccent = Color(red: 0.38, green: 0.48, blue: 0.98)
    static let textSecondary = Color.white.opacity(0.66)
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(ShelfTheme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            .foregroundStyle(Color.black.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 3)
            }
            .shadow(color: isFocused ? ShelfTheme.accent.opacity(0.55) : .clear, radius: 13)
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1))
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(configuration.isPressed ? 0.18 : 0.10))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? ShelfTheme.accent : Color.white.opacity(0.12), lineWidth: isFocused ? 3 : 1)
            )
            .shadow(color: isFocused ? ShelfTheme.accent.opacity(0.45) : .clear, radius: 13)
            .scaleEffect(configuration.isPressed ? 0.97 : (isFocused ? 1.06 : 1))
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}
