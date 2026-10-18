import Foundation

/// Which colour scheme the reader wants, independent of which palette they picked.
///
/// Dark is the default. The two axes are deliberately separate: a palette says what the
/// paper and ink are made of, an appearance says whether the lamp is on.
public enum AppearancePreference: String, CaseIterable, Sendable, Identifiable, Codable {
    case dark
    case light
    case system

    public static let standard = AppearancePreference.dark

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Automatic"
        }
    }
}

/// Where the appearance choice is stored.
///
/// The keys are named here, rather than written out at each end, so the modifier that
/// reads them and the screen that writes them cannot drift apart — and so moving to an
/// App Group for a future widget is one edit in one place.
///
/// This is a per-device display preference, not the user's data: it stays in
/// `UserDefaults` and deliberately does **not** sync through CloudKit with the log.
public enum AppearanceDefaults {
    public static let appearance = "appearance.preference"
    public static let palette = "appearance.palette"
}
