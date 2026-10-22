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
    /// A visit that began with marking a trail hiked.
    case hike

    public var name: String {
        switch self {
        case .manual: "Checked in"
        case .autoDetected: "Detected"
        case .photoImport: "From photos"
        case .stamp: "Stamped"
        case .hike: "Hiked"
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
        case .active: "Under way"
        case .done: "Done"
        }
    }

    /// A trip's status on `now`, from its dates where it has them: planned before its
    /// first day, under way through its last, done after. An undated trip keeps the
    /// status the reader gave it, which is the only thing that can say.
    public static func on(
        _ now: Date,
        start: Date?,
        end: Date?,
        stored: TripStatus,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> TripStatus {
        guard let start else { return stored }
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: max(end ?? start, start))
        if today < first {
            return .planned
        }
        return today <= last ? .active : .done
    }
}

/// What a trip stop is: a place, or something inside one or near it
/// (SPECIFICATION.md §10, itinerary stops).
///
/// A stop always belongs to a place — the park a sight or trail is in, the park a motel
/// is for — so a trip's places, its planned styling on the map and its saved documents
/// still read from the place, whatever the stop is.
public enum StopTarget: Hashable, Sendable {
    case place
    case pointOfInterest(UnigridsID)
    case trail(UnigridsID)
    /// Somewhere to sleep, found by name.
    case lodging(name: String, location: Coordinate)
    /// Anywhere else the reader wants on the way: a viewpoint, a diner, a ferry.
    case custom(name: String, location: Coordinate)

    /// The stored form of the kind, as `TripStop.targetKindRaw` keeps it.
    public var kindRaw: String {
        switch self {
        case .place: "place"
        case .pointOfInterest: "pointOfInterest"
        case .trail: "trail"
        case .lodging: "lodging"
        case .custom: "custom"
        }
    }

    /// The stop's own coordinate, where it has one independent of reference data.
    public var ownLocation: Coordinate? {
        switch self {
        case let .lodging(_, location), let .custom(_, location): location
        case .place, .pointOfInterest, .trail: nil
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

/// Which trip a visit logged without one belongs to (SPECIFICATION.md §9: "a check-in
/// can join a trip").
///
/// Conservative on purpose, because nothing asks the reader: a dated trip that lists the
/// place and whose days cover the visit's day; failing that, while logging live rather
/// than back-dating, the one unfinished undated trip that lists the place. Anything less
/// certain stays loose, and the reader can move it.
public enum TripMatching {
    public struct Candidate: Sendable {
        public let id: UUID
        public let start: Date?
        public let end: Date?
        public let status: TripStatus
        public let listsPlace: Bool

        public init(id: UUID, start: Date?, end: Date?, status: TripStatus, listsPlace: Bool) {
            self.id = id
            self.start = start
            self.end = end
            self.status = status
            self.listsPlace = listsPlace
        }
    }

    public static func trip(
        for date: Date,
        among candidates: [Candidate],
        now: Date = Date(),
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> UUID? {
        let listing = candidates.filter(\.listsPlace)
        let day = calendar.startOfDay(for: date)
        let covering = listing.filter { candidate in
            guard let start = candidate.start else { return false }
            let first = calendar.startOfDay(for: start)
            let last = calendar.startOfDay(for: max(candidate.end ?? start, start))
            return first <= day && day <= last
        }
        if covering.count == 1 {
            return covering[0].id
        }
        guard covering.isEmpty, abs(date.timeIntervalSince(now)) < 36 * 3600 else { return nil }
        let undated = listing.filter { $0.start == nil && $0.status != .done }
        return undated.count == 1 ? undated[0].id : nil
    }
}
