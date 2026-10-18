import Foundation

/// A visit, reduced to what the stats need.
///
/// `UnigridsLog` maps its SwiftData records into these so the whole stats layer stays pure
/// and testable without a model container.
public struct VisitSummary: Hashable, Sendable {
    public let placeID: UnigridsID
    public let date: Date

    public init(placeID: UnigridsID, date: Date) {
        self.placeID = placeID
        self.date = date
    }
}

/// A hiked trail, reduced to what the stats need.
public struct HikeSummary: Hashable, Sendable {
    public let trailID: UnigridsID
    public let date: Date
    public let completion: HikeCompletion

    public init(trailID: UnigridsID, date: Date, completion: HikeCompletion) {
        self.trailID = trailID
        self.date = date
        self.completion = completion
    }
}

/// How far through a set of places the user is.
public struct Completion: Hashable, Sendable {
    public let visited: Int
    public let total: Int

    public init(visited: Int, total: Int) {
        self.visited = visited
        self.total = total
    }

    /// 0 when there is nothing to complete, so the ring has something safe to draw.
    public var fraction: Double {
        total > 0 ? Double(visited) / Double(total) : 0
    }

    /// `23 of 63`.
    public var description: String {
        "\(visited) of \(total)"
    }
}

/// Progress through one theme: "4 of 6 volcanic parks seen" (SPECIFICATION.md §11).
public struct ThemeProgress: Hashable, Sendable, Identifiable {
    public let theme: Theme
    public let completion: Completion

    public var id: UnigridsID {
        theme.id
    }
}

/// Everything the Stats tab shows, computed in one pass from the log plus bundled
/// reference data (SPECIFICATION.md §11).
///
/// Pure and synchronous: no store, no network, no weather call. Weather is read from the
/// snapshot stored with each visit, so stats never depend on a live request.
public struct StatsReport: Sendable {
    public let nationalParks: Completion
    public let allPlaces: Completion
    public let states: Completion
    public let regions: Completion
    public let visitedStates: [USState]
    public let visitedRegions: [PassportRegion]
    public let visitsByYear: [YearCount]
    public let visitsBySeason: [SeasonCount]
    public let themeProgress: [ThemeProgress]
    public let firstVisit: Date?
    public let latestVisit: Date?
    public let totalVisits: Int
    public let distanceHikedMetres: Double
    public let elevationGainedMetres: Double
    public let longestHikeMetres: Double
    public let highestPointMetres: Double?
    public let nearestUnvisited: NearbyPlace?

    public struct YearCount: Hashable, Sendable, Identifiable {
        public let year: Int
        public let count: Int
        public var id: Int {
            year
        }
    }

    public struct SeasonCount: Hashable, Sendable, Identifiable {
        public let season: Season
        public let count: Int
        public var id: String {
            season.rawValue
        }
    }

    public struct NearbyPlace: Hashable, Sendable {
        public let place: Place
        public let distanceMetres: Double
    }

    /// Gain expressed in Everests, as §11 asks.
    public var everestsClimbed: Double {
        elevationGainedMetres / UnigridsFormat.everestMetres
    }

    public init(
        places: [Place],
        visits: [VisitSummary],
        hikes: [HikeSummary] = [],
        trails: [Trail] = [],
        themes: [Theme] = [],
        origin: Coordinate? = nil,
        calendar: Calendar = .current
    ) {
        let visitedPlaceIDs = Set(visits.map(\.placeID))
        let placesByID = Dictionary(
            places.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // A visit can outlive the reference data it points at, so an unresolved place
        // drops out of coverage while the visit itself still counts.
        let visitedPlaces = visitedPlaceIDs.compactMap { placesByID[$0] }
        let parks = places.filter { $0.tier == .nationalPark }

        nationalParks = Completion(
            visited: parks.count { visitedPlaceIDs.contains($0.id) },
            total: parks.count
        )
        allPlaces = Completion(visited: visitedPlaces.count, total: places.count)

        visitedStates = Self.states(in: visitedPlaces)
        states = Completion(visited: visitedStates.count, total: USState.all.count)
        visitedRegions = Self.regions(in: visitedPlaces)
        regions = Completion(
            visited: visitedRegions.count,
            total: PassportRegion.allCases.count
        )

        visitsByYear = Self.byYear(visits, calendar: calendar)
        visitsBySeason = Self.bySeason(visits, calendar: calendar)
        themeProgress = Self.progress(
            themes: themes,
            places: places,
            visitedPlaceIDs: visitedPlaceIDs
        )

        let dates = visits.map(\.date).sorted()
        firstVisit = dates.first
        latestVisit = dates.last
        totalVisits = visits.count

        let totals = Self.trailTotals(hikes: hikes, trails: trails)
        distanceHikedMetres = totals.distance
        elevationGainedMetres = totals.gain
        longestHikeMetres = totals.longest
        highestPointMetres = totals.highest

        nearestUnvisited = Self.nearest(
            to: origin,
            among: parks.filter { !visitedPlaceIDs.contains($0.id) }
        )
    }

    // MARK: - Pieces

    private static func states(in places: [Place]) -> [USState] {
        let codes = Set(places.flatMap { $0.states.map(\.code) })
        return USState.all.filter { codes.contains($0.code) }
    }

    private static func regions(in places: [Place]) -> [PassportRegion] {
        let visited = Set(places.map(\.resolvedPassportRegion))
        return PassportRegion.allCases.filter { visited.contains($0) }
    }

    private static func byYear(
        _ visits: [VisitSummary],
        calendar: Calendar
    ) -> [YearCount] {
        var counts: [Int: Int] = [:]
        for visit in visits {
            guard let year = calendar.dateComponents([.year], from: visit.date).year
            else { continue }
            counts[year, default: 0] += 1
        }
        return counts
            .sorted { $0.key < $1.key }
            .map { YearCount(year: $0.key, count: $0.value) }
    }

    private static func bySeason(
        _ visits: [VisitSummary],
        calendar: Calendar
    ) -> [SeasonCount] {
        var counts: [Season: Int] = [:]
        for visit in visits {
            guard let month = calendar.dateComponents([.month], from: visit.date).month
            else { continue }
            counts[Season.forMonth(month), default: 0] += 1
        }
        return Season.allCases.map { SeasonCount(season: $0, count: counts[$0] ?? 0) }
    }

    private static func progress(
        themes: [Theme],
        places: [Place],
        visitedPlaceIDs: Set<UnigridsID>
    ) -> [ThemeProgress] {
        themes
            .map { theme in
                let tagged = places.filter { $0.themes.contains(theme.id) }
                return ThemeProgress(
                    theme: theme,
                    completion: Completion(
                        visited: tagged.count { visitedPlaceIDs.contains($0.id) },
                        total: tagged.count
                    )
                )
            }
            .filter { $0.completion.total > 0 }
            .sorted { $0.theme.name < $1.theme.name }
    }

    private struct TrailTotals {
        var distance = 0.0
        var gain = 0.0
        var longest = 0.0
        var highest: Double?
    }

    private static func trailTotals(hikes: [HikeSummary], trails: [Trail]) -> TrailTotals {
        let trailsByID = Dictionary(
            trails.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var totals = TrailTotals()
        for hike in hikes {
            guard let trail = trailsByID[hike.trailID] else { continue }
            // A partial hike counts half its length and gain. Crude, but honest: the app
            // does not record where the user turned back, so it must not claim precision
            // it does not have — and it must not claim the summit either.
            let share = hike.completion == .full ? 1.0 : 0.5
            totals.distance += trail.lengthMetres * share
            totals.gain += trail.gainMetres * share
            totals.longest = max(totals.longest, trail.lengthMetres * share)
            if hike.completion == .full, let point = trail.highPointMetres {
                totals.highest = max(totals.highest ?? point, point)
            }
        }
        return totals
    }

    private static func nearest(
        to origin: Coordinate?,
        among places: [Place]
    ) -> NearbyPlace? {
        guard let origin else { return nil }
        return places
            .map { NearbyPlace(place: $0, distanceMetres: origin.distance(to: $0.centre)) }
            .min { $0.distanceMetres < $1.distanceMetres }
    }
}
