import Foundation
import SwiftData
import UnigridsCore

// The user's own data, synced through their private CloudKit database
// (SPECIFICATION.md §13, docs/adr/0002).
//
// Three constraints shape every model here, and all three come from CloudKit:
//
//  1. Every attribute needs a default or must be optional, or the container will not
//     initialise against CloudKit.
//  2. No unique constraints. Identity is a stored `UUID` the app generates.
//  3. Every relationship is optional and has an explicit inverse.
//
// A fourth constraint comes from the reference data: these records point at places,
// points of interest and trails **only** by `UnigridsID` string, because the reference
// dataset is replaced wholesale on each release (AGENTS.md §4). An id that stops
// resolving leaves the record intact and renders as an unknown place.

/// A trip, which is both the planner's unit and the log's (SPECIFICATION.md §10).
@Model
public final class Trip {
    public private(set) var id: UUID = UUID()
    public var name: String = ""
    public var startDate: Date?
    public var endDate: Date?
    /// Stored raw so an unknown future value degrades to `.planned` instead of failing
    /// to decode.
    public var statusRaw: String = TripStatus.planned.rawValue
    public var notes: String = ""
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Visit.trip)
    public var visits: [Visit]? = []

    @Relationship(deleteRule: .cascade, inverse: \Reminder.trip)
    public var reminders: [Reminder]? = []

    public var status: TripStatus {
        get { TripStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    public init(
        name: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        status: TripStatus = .planned,
        notes: String = ""
    ) {
        id = UUID()
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        statusRaw = status.rawValue
        self.notes = notes
        createdAt = Date()
    }
}

/// A visit to one place. The unit everything else in the log hangs from.
@Model
public final class Visit {
    public private(set) var id: UUID = UUID()
    /// `UnigridsID` of the place visited, as a string.
    public var placeID: String = ""
    public var date: Date = Date()
    public var endDate: Date?
    public var sourceRaw: String = VisitSource.manual.rawValue
    /// 1 to 5, or nil when the user did not rate it.
    public var rating: Int?
    public var notes: String = ""
    public var createdAt: Date = Date()

    public var trip: Trip?

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.visit)
    public var checkIns: [CheckIn]? = []

    @Relationship(deleteRule: .cascade, inverse: \Hike.visit)
    public var hikes: [Hike]? = []

    @Relationship(deleteRule: .nullify, inverse: \Stamp.visit)
    public var stamps: [Stamp]? = []

    @Relationship(deleteRule: .cascade, inverse: \WeatherSnapshot.visit)
    public var weather: WeatherSnapshot?

    public var source: VisitSource {
        get { VisitSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public var place: UnigridsID {
        UnigridsID(placeID)
    }

    public var summary: VisitSummary {
        VisitSummary(placeID: UnigridsID(placeID), date: date)
    }

    public init(
        placeID: UnigridsID,
        date: Date = Date(),
        endDate: Date? = nil,
        source: VisitSource = .manual,
        rating: Int? = nil,
        notes: String = "",
        trip: Trip? = nil
    ) {
        id = UUID()
        self.placeID = placeID.rawValue
        self.date = date
        self.endDate = endDate
        sourceRaw = source.rawValue
        self.rating = rating
        self.notes = notes
        self.trip = trip
        createdAt = Date()
    }
}

/// A check-in at a sight, visitor centre or trail within a visit.
@Model
public final class CheckIn {
    public private(set) var id: UUID = UUID()
    /// `place`, `pointOfInterest` or `trail`.
    public var targetKindRaw: String = "pointOfInterest"
    public var targetID: String = ""
    public var date: Date = Date()
    /// Photos library asset identifiers. References only — never copies of the originals
    /// (SPECIFICATION.md §9, §15).
    public var photoAssetIdentifiers: [String] = []
    public var notes: String = ""

    public var visit: Visit?

    public var target: CheckInTarget {
        let id = UnigridsID(targetID)
        switch targetKindRaw {
        case "place": return .place(id)
        case "trail": return .trail(id)
        default: return .pointOfInterest(id)
        }
    }

    public init(target: CheckInTarget, date: Date = Date(), notes: String = "") {
        id = UUID()
        switch target {
        case let .place(id):
            targetKindRaw = "place"
            targetID = id.rawValue
        case let .pointOfInterest(id):
            targetKindRaw = "pointOfInterest"
            targetID = id.rawValue
        case let .trail(id):
            targetKindRaw = "trail"
            targetID = id.rawValue
        }
        self.date = date
        self.notes = notes
    }
}

/// A trail walked, in full or in part.
@Model
public final class Hike {
    public private(set) var id: UUID = UUID()
    public var trailID: String = ""
    public var date: Date = Date()
    public var completionRaw: String = HikeCompletion.full.rawValue

    public var visit: Visit?

    public var completion: HikeCompletion {
        get { HikeCompletion(rawValue: completionRaw) ?? .full }
        set { completionRaw = newValue.rawValue }
    }

    public var summary: HikeSummary {
        HikeSummary(trailID: UnigridsID(trailID), date: date, completion: completion)
    }

    public init(trailID: UnigridsID, date: Date = Date(), completion: HikeCompletion = .full) {
        id = UUID()
        self.trailID = trailID.rawValue
        self.date = date
        completionRaw = completion.rawValue
    }
}

/// One passport impression (SPECIFICATION.md §9).
///
/// The America 250 seal is **not** stored: it is derived from `date` every time it is
/// drawn, so the rule and the data can never disagree.
@Model
public final class Stamp {
    public private(set) var id: UUID = UUID()
    public var placeID: String = ""
    /// The specific official stamp location, where a site has more than one. A site with
    /// several locations gets one passport slot per location.
    public var stampLocationID: String?
    public var date: Date = Date()
    /// `StampImpression`'s seed. Stored as `Int64` because that is what the store and
    /// CloudKit carry; the bit pattern round-trips exactly.
    public var seedBits: Int64 = 0
    /// Set when the stamp was made on site, confirmed by location.
    public var isVerifiedOnSite: Bool = false
    /// The user also has the paper cancellation, which helps paper collectors see what
    /// they still need.
    public var realStampCollected: Bool = false
    public var createdAt: Date = Date()

    public var visit: Visit?

    public var seed: UInt64 {
        UInt64(bitPattern: seedBits)
    }

    public var impression: StampImpression {
        StampImpression(seed: seed)
    }

    public var place: UnigridsID {
        UnigridsID(placeID)
    }

    public var stampLocation: UnigridsID? {
        stampLocationID.map { UnigridsID($0) }
    }

    /// Whether this impression carries the America 250 overprint.
    public func hasAmerica250Seal(calendar: Calendar = .current) -> Bool {
        America250.applies(to: date, calendar: calendar)
    }

    public init(
        placeID: UnigridsID,
        stampLocationID: UnigridsID? = nil,
        date: Date = Date(),
        seed: UInt64 = StampImpression.newSeed(),
        isVerifiedOnSite: Bool = false,
        realStampCollected: Bool = false,
        visit: Visit? = nil
    ) {
        id = UUID()
        self.placeID = placeID.rawValue
        self.stampLocationID = stampLocationID?.rawValue
        self.date = date
        seedBits = Int64(bitPattern: seed)
        self.isVerifiedOnSite = isVerifiedOnSite
        self.realStampCollected = realStampCollected
        self.visit = visit
        createdAt = Date()
    }
}

/// A reminder for a permit window, timed-entry slot or booking opening
/// (SPECIFICATION.md §10).
@Model
public final class Reminder {
    public enum Kind: String, CaseIterable, Sendable, Codable {
        case permit
        case timedEntry
        case bookingWindow

        public var name: String {
            switch self {
            case .permit: "Permit"
            case .timedEntry: "Timed entry"
            case .bookingWindow: "Booking window"
            }
        }
    }

    public private(set) var id: UUID = UUID()
    public var kindRaw: String = Kind.permit.rawValue
    public var date: Date = Date()
    public var title: String = ""
    /// A deep link to Recreation.gov or the park's own page. Unigrids never handles
    /// bookings or payments itself.
    public var urlString: String?

    public var trip: Trip?

    public var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .permit }
        set { kindRaw = newValue.rawValue }
    }

    public var url: URL? {
        urlString.flatMap(URL.init(string:))
    }

    public init(
        kind: Kind,
        date: Date,
        title: String,
        url: URL? = nil,
        trip: Trip? = nil
    ) {
        id = UUID()
        kindRaw = kind.rawValue
        self.date = date
        self.title = title
        urlString = url?.absoluteString
        self.trip = trip
    }
}

/// The weather at a visit, captured once when the visit is logged.
///
/// Stats never make a live weather call (SPECIFICATION.md §11): WeatherKit covers recent
/// dates and the Open-Meteo archive covers older ones, and whichever answered is recorded
/// here so the figure never changes under the user.
@Model
public final class WeatherSnapshot {
    public enum Source: String, Sendable, Codable {
        case weatherKit
        case openMeteoArchive

        public var attribution: String {
            switch self {
            case .weatherKit: "Weather data provided by Apple Weather"
            case .openMeteoArchive: "Historical weather from Open-Meteo (ERA5), CC BY 4.0"
            }
        }
    }

    public private(set) var id: UUID = UUID()
    public var date: Date = Date()
    public var highCelsius: Double?
    public var lowCelsius: Double?
    public var precipitationMillimetres: Double?
    /// The condition as the source described it, kept as text rather than mapped to an
    /// enum the sources do not share.
    public var condition: String?
    public var sourceRaw: String = Source.weatherKit.rawValue

    public var visit: Visit?

    public var source: Source {
        get { Source(rawValue: sourceRaw) ?? .weatherKit }
        set { sourceRaw = newValue.rawValue }
    }

    public init(
        date: Date,
        highCelsius: Double? = nil,
        lowCelsius: Double? = nil,
        precipitationMillimetres: Double? = nil,
        condition: String? = nil,
        source: Source
    ) {
        id = UUID()
        self.date = date
        self.highCelsius = highCelsius
        self.lowCelsius = lowCelsius
        self.precipitationMillimetres = precipitationMillimetres
        self.condition = condition
        sourceRaw = source.rawValue
    }
}
