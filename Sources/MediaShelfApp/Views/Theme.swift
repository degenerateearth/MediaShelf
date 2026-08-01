import SwiftUI

enum ShelfTheme {
    static let canvas = Color(red: 0.018, green: 0.022, blue: 0.030)
    static let background = canvas
    static let surface = Color(red: 0.050, green: 0.057, blue: 0.071)
    static let surfaceRaised = Color(red: 0.075, green: 0.084, blue: 0.102)
    static let elevated = surfaceRaised
    static let accent = Color(red: 0.29, green: 0.82, blue: 0.76)
    static let secondaryAccent = Color(red: 0.39, green: 0.46, blue: 0.92)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color.white.opacity(0.67)
    static let textTertiary = Color.white.opacity(0.43)
    static let hairline = Color.white.opacity(0.10)

    static let ambientBackground = LinearGradient(
        colors: [
            Color(red: 0.035, green: 0.043, blue: 0.060),
            canvas,
            Color(red: 0.016, green: 0.020, blue: 0.028),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.80 : 0.96))
            .foregroundStyle(Color.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isFocused ? Color.white : .clear, lineWidth: 2)
            }
            .shadow(color: .black.opacity(isFocused ? 0.42 : 0.20), radius: isFocused ? 18 : 8, y: 7)
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.035 : 1))
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isFocused)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(configuration.isPressed ? 0.20 : 0.115))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isFocused ? Color.white.opacity(0.92) : ShelfTheme.hairline, lineWidth: isFocused ? 2 : 1)
            )
            .shadow(color: .black.opacity(isFocused ? 0.38 : 0.14), radius: isFocused ? 17 : 7, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.035 : 1))
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isFocused)
    }
}

typealias PremiumSecondaryButtonStyle = SecondaryButtonStyle
