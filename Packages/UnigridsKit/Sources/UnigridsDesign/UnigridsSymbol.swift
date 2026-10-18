import SwiftUI
import UnigridsCore

/// Every icon the app draws, named by what it means rather than by what it looks like.
///
/// One table, for two reasons. An unknown `systemName` renders as blank space instead of
/// failing the build, so symbol names need somewhere they can be checked in one pass —
/// `stamp` and `stamp.fill` were drawn in five places for months and exist in no version
/// of SF Symbols. And a vocabulary scattered across fifty call sites drifts: outline here,
/// filled there, two symbols for one idea.
///
/// The fill rule, which the whole set follows: **outline by default; filled only for a
/// place on a map, and for something done.** A filled glyph reads as a pin or a tick; an
/// outlined one reads as an action or a label.
public enum UnigridsSymbol: String, CaseIterable, Sendable {
    // Tabs
    case map
    case parks = "tree"
    case trips = "suitcase"
    case passport = "book.closed"
    case stats = "chart.bar"

    // Actions
    case checkIn = "mappin.and.ellipse"
    case openGuide = "book.pages"
    case directions = "car"
    case website = "safari"
    case settings = "gearshape"
    case delete = "trash"
    case add = "plus"

    // Status
    case visited = "checkmark.circle.fill"
    case planned = "circle.dashed"
    case seen = "checkmark"
    case verified = "checkmark.seal.fill"
    case rated = "star.fill"
    case unrated = "star"
    case commemorative = "seal.fill"
    case commemorativeOutline = "seal"

    // Stats
    case recentVisit = "clock.arrow.circlepath"
    case distance = "figure.walk"
    case elevation = "arrow.up.right"
    case highPoint = "mountain.2"
    case pending = "hourglass"
    case scheduled = "calendar.badge.clock"

    // Problems
    case warning = "exclamationmark.triangle"
    case warningFilled = "exclamationmark.triangle.fill"
    case storeUnavailable = "exclamationmark.icloud"

    /// The SF Symbol name. Every one is checked against the SDK by `UnigridsDesignTests`.
    public var systemName: String {
        rawValue
    }

    /// A place on the map, by what kind of place it is.
    ///
    /// Filled throughout, because every one of these is a pin: the fill is what separates
    /// "a place" from "an action" at a glance.
    public static func place(_ kind: PlaceKind) -> String {
        switch kind {
        case .nationalPark: "tree.fill"
        case .npsUnit: "building.columns.fill"
        case .statePark: "leaf.fill"
        case .nationalForest, .nationalGrassland: "tree.fill"
        case .blmMonument, .blmConservationArea: "mountain.2.fill"
        case .wildlifeRefuge: "bird.fill"
        case .naturalLandmark: "sparkles"
        case .scenicByway: "road.lanes"
        }
    }
}

extension Image {
    /// An icon from the app's vocabulary.
    public init(_ symbol: UnigridsSymbol) {
        self.init(systemName: symbol.systemName)
    }
}

extension Label where Title == Text, Icon == Image {
    /// A labelled icon from the app's vocabulary.
    public init(_ title: LocalizedStringKey, symbol: UnigridsSymbol) {
        self.init(title, systemImage: symbol.systemName)
    }
}
