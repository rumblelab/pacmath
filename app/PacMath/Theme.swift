import SwiftUI

enum Theme {
    // MARK: - Colors

    static let background = Color(red: 0x21 / 255.0, green: 0x00 / 255.0, blue: 0x5D / 255.0) // #21005D
    static let accent = Color(red: 250 / 255.0, green: 128 / 255.0, blue: 114 / 255.0)         // salmon
    static let correctGreen = Color(red: 0x7B / 255.0, green: 0xE0 / 255.0, blue: 0x92 / 255.0) // #7BE092
    static let streakYellow = Color(red: 255 / 255.0, green: 215 / 255.0, blue: 0 / 255.0) // vibrant gold/pac-man yellow
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let cardBackground = Color.white.opacity(0.08)
    static let borderColor = Color.white.opacity(0.3)

    // MARK: - Typography

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - View Extensions

extension View {
    func resultCard() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
