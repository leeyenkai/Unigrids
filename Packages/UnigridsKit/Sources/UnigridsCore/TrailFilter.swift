import Foundation

/// Which trails the catalogue lists (SPECIFICATION.md §8, "Filters"): length, climb,
/// effort, loops, features, and the reader's own log.
public struct TrailFilter: Hashable, Sendable {
    public enum Length: String, CaseIterable, Sendable, Identifiable {
        case any
        case short
        case medium
        case long

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .any: "Any length"
            case .short: "Under 5 km there and back"
            case .medium: "5 to 15 km there and back"
            case .long: "Over 15 km there and back"
            }
        }

        public func contains(_ metres: Double) -> Bool {
            switch self {
            case .any: true
            case .short: metres < 5000
            case .medium: metres >= 5000 && metres <= 15000
            case .long: metres > 15000
            }
        }
    }

    public enum Sort: String, CaseIterable, Sendable, Identifiable {
        case length
        case climb
        case effort
        case name

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .length: "Longest first"
            case .climb: "Most climb first"
            case .effort: "Easiest first"
            case .name: "A to Z"
            }
        }
    }

    public var length: Length
    /// Empty means every effort band, including unmeasured trails.
    public var difficulties: Set<TrailDifficulty>
    public var features: Set<TrailFeature>
    public var loopsOnly: Bool
    public var notYetHiked: Bool
    public var query: String

    public init(
        length: Length = .any,
        difficulties: Set<TrailDifficulty> = [],
        features: Set<TrailFeature> = [],
        loopsOnly: Bool = false,
        notYetHiked: Bool = false,
        query: String = ""
    ) {
        self.length = length
        self.difficulties = difficulties
        self.features = features
        self.loopsOnly = loopsOnly
        self.notYetHiked = notYetHiked
        self.query = query
    }

    public var isNarrowed: Bool {
        length != .any || !difficulties.isEmpty || !features.isEmpty || loopsOnly || notYetHiked
    }

    public func includes(_ trail: Trail, hiked: Bool) -> Bool {
        guard length.contains(trail.walkedMetres) else { return false }
        if !difficulties.isEmpty {
            guard let effort = trail.estimatedDifficulty, difficulties.contains(effort)
            else { return false }
        }
        if !features.isEmpty, features.isDisjoint(with: trail.features) {
            return false
        }
        if loopsOnly, trail.routeType != .loop {
            return false
        }
        if notYetHiked, hiked {
            return false
        }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty, !trail.name.localizedCaseInsensitiveContains(needle) {
            return false
        }
        return true
    }

    /// Trails in the chosen order. Unmeasured trails sort after measured ones on climb and
    /// effort, rather than as if they climbed nothing.
    public static func sorted(_ trails: [Trail], by sort: Sort) -> [Trail] {
        switch sort {
        case .length:
            trails.sorted { ($0.walkedMetres, $1.name) > ($1.walkedMetres, $0.name) }
        case .climb:
            trails.sorted {
                ($0.climbMetres ?? -1, $1.name) > ($1.climbMetres ?? -1, $0.name)
            }
        case .effort:
            trails.sorted { first, second in
                let band = { (trail: Trail) -> Int in
                    trail.estimatedDifficulty.flatMap(TrailDifficulty.allCases.firstIndex)
                        ?? Int.max
                }
                return (band(first), first.walkedMetres, first.name)
                    < (band(second), second.walkedMetres, second.name)
            }
        case .name:
            trails.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
