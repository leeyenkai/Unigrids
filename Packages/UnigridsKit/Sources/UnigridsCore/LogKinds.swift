import Foundation

/// How a visit got into the log (SPECIFICATION.md §9).
///
/// Every route ends in the same structure, and nothing is logged without the user
/// confirming it — the source records which route they confirmed, not who decided.
public enum VisitSource: String, CaseIterable, Sendable, Codable {
    case manual
    case autoDetected
    case photoImport
    case stamp

    public var name: String {
        switch self {
        case .manual: "Checked in"
        case .autoDetected: "Detected"
        case .photoImport: "From photos"
        case .stamp: "Stamped"
        }
    }
}

/// Where a trip is in its life (SPECIFICATION.md §10).
///
/// One object serves the planner and the log: a trip starts as a plan, becomes active on
/// its first day, and turns into a logged trip as the user checks in.
public enum TripStatus: String, CaseIterable, Sendable, Codable {
    case planned
    case active
    case done

    public var name: String {
        switch self {
        case .planned: "Planned"
        case .active: "Active"
        case .done: "Done"
        }
    }
}

/// What a check-in attached itself to.
public enum CheckInTarget: Hashable, Sendable {
    case place(UnigridsID)
    case pointOfInterest(UnigridsID)
    case trail(UnigridsID)

    public var id: UnigridsID {
        switch self {
        case let .place(id), let .pointOfInterest(id), let .trail(id): id
        }
    }
}

/// Whether a trail was walked end to end.
public enum HikeCompletion: String, CaseIterable, Sendable, Codable {
    case full
    case partial

    public var name: String {
        switch self {
        case .full: "Completed"
        case .partial: "Part way"
        }
    }
}
