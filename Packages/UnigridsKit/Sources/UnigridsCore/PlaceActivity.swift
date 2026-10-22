import Foundation

/// Something a visitor can do at a place, for the map's activity filter
/// (SPECIFICATION.md §5, "Filters").
///
/// Read from the NPS Data API's activity list, which names some sixty activities; the
/// filter needs a dozen, so the pipeline folds the NPS's names into these. Places outside
/// the NPS carry none: no source lists their activities, and the filter treats them as
/// unknown rather than guessing.
public enum PlaceActivity: String, CaseIterable, Sendable, Codable, Identifiable {
    case hiking
    case camping
    case scenicDriving
    case wildlifeWatching
    case paddling
    case fishing
    case stargazing
    case biking
    case swimming
    case winterSports
    case climbing
    case museums

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .hiking: "Hiking"
        case .camping: "Camping"
        case .scenicDriving: "Scenic driving"
        case .wildlifeWatching: "Wildlife watching"
        case .paddling: "Boating and paddling"
        case .fishing: "Fishing"
        case .stargazing: "Stargazing"
        case .biking: "Biking"
        case .swimming: "Swimming"
        case .winterSports: "Winter sports"
        case .climbing: "Climbing"
        case .museums: "Museums and exhibits"
        }
    }
}
