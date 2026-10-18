import Foundation

/// The family a theme belongs to (SPECIFICATION.md §11).
public enum ThemeFamily: String, CaseIterable, Sendable, Codable, Identifiable {
    case geology
    case ecosystem
    case history

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .geology: "Geology"
        case .ecosystem: "Ecosystem"
        case .history: "History"
        }
    }
}

/// A theme tag on a place — "canyons", "volcanoes", "desert", "reef" — seeded from NPS
/// API topics and activities and curated in the pipeline.
///
/// Themes drive the "themes and landscapes" family of stats: "4 of 6 volcanic parks seen".
public struct Theme: Identifiable, Hashable, Sendable, Codable {
    public let id: UnigridsID
    public let family: ThemeFamily
    public let name: String

    public init(id: UnigridsID, family: ThemeFamily, name: String) {
        self.id = id
        self.family = family
        self.name = name
    }
}
