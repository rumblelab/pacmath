import SwiftUI
import Observation

@Observable
class ChompyProfile {
    static let shared = ChompyProfile()

    private static let nameKey = "chompyName"
    private static let colorIndexKey = "chompyColorIndex"
    private static let maxNameLength = 12

    var name: String {
        didSet {
            if name.count > Self.maxNameLength {
                name = String(name.prefix(Self.maxNameLength))
                return
            }
            UserDefaults.standard.set(name, forKey: Self.nameKey)
        }
    }

    var colorIndex: Int {
        didSet {
            UserDefaults.standard.set(colorIndex, forKey: Self.colorIndexKey)
        }
    }

    private init() {
        self.name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        self.colorIndex = UserDefaults.standard.integer(forKey: Self.colorIndexKey)
    }

    /// User-facing name. Falls back to "chompy" when the user hasn't set one.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "chompy" : trimmed
    }

    var color: Color {
        let clamped = max(0, min(colorIndex, Self.palette.count - 1))
        return Self.palette[clamped].color
    }

    struct PaletteEntry: Identifiable {
        let id: Int
        let label: String
        let color: Color
    }

    static let palette: [PaletteEntry] = [
        PaletteEntry(id: 0, label: "gold",   color: Theme.streakYellow),
        PaletteEntry(id: 1, label: "mint",   color: Theme.correctGreen),
        PaletteEntry(id: 2, label: "salmon", color: Theme.accent),
        PaletteEntry(id: 3, label: "sky",    color: Color(red: 0.45, green: 0.80, blue: 0.98)),
        PaletteEntry(id: 4, label: "grape",  color: Color(red: 0.73, green: 0.55, blue: 0.98)),
    ]
}
