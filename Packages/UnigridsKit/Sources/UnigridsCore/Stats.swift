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

extension VisitSummary {
    /// The visit re-dated to noon, in `calendar`, on the day it fell on at its place
    /// (ADR 0012). The stats reckon years, months, seasons and streaks in the reader's
    /// calendar, and without this a visit to Shiretoko on 1 January, stored as noon in
    /// Tokyo, would count as 31 December to a reader in California.
    public func onPlaceDay(_ placeCalendar: Calendar, in calendar: Calendar) -> VisitSummary {
        VisitSummary(
            placeID: placeID,
            date: UnigridsCalendar.noon(onDayOf: date, shownIn: placeCalendar, in: calendar)
        )
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

    /// The hike re-dated onto its park's own day, as `VisitSummary.onPlaceDay` does.
    public func onPlaceDay(_ placeCalendar: Calendar, in calendar: Calendar) -> HikeSummary {
        HikeSummary(
            trailID: trailID,
            date: UnigridsCalendar.noon(onDayOf: date, shownIn: placeCalendar, in: calendar),
            completion: completion
        )
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
    /// National parks visited, country by country, for each country in the data — the
    /// US first. `nationalParks` is every country's together.
    public let nationalParksByCountry: [CountryCompletion]
    /// States, prefectures or counties visited, by country.
    public let subdivisionsByCountry: [CountryCompletion]
    /// Passport regions with a visit, by book.
    public let regionsByCountry: [CountryCompletion]
    /// Countries visited, out of those the data covers.
    public let countries: Completion

    /// One country's share of a figure.
    public struct CountryCompletion: Hashable, Sendable, Identifiable {
        public let country: Country
        public let completion: Completion
        public var id: Country {
            country
        }
    }

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
        calendar: Calendar = UnigridsCalendar.gregorian()
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
        // Places and themes are counted over the countries the reader has been to — the
        // US before any visit — so a reader who has never left the US keeps the figures
        // they had, rather than finding Japan's volcanoes in their denominator.
        let scope = Set(visitedPlaces.map(\.country)).union(
            visitedPlaces.isEmpty ? [.unitedStates] : []
        )
        let counted = places.filter { scope.contains($0.country) }
        allPlaces = Completion(visited: visitedPlaces.count, total: counted.count)

        visitedStates = Self.states(in: visitedPlaces)
        states = Completion(visited: visitedStates.count, total: USState.all.count)
        visitedRegions = Self.regions(in: visitedPlaces)
        // The US book's nine until Stats counts each country's book (ADR 0013).
        regions = Completion(
            visited: visitedRegions.count,
            total: PassportRegion.regions(in: .unitedStates).count
        )

        visitsByYear = Self.byYear(visits, calendar: calendar)
        visitsBySeason = Self.bySeason(visits, calendar: calendar)
        themeProgress = Self.progress(
            themes: themes,
            places: counted,
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

        let byCountry = Self.byCountry(
            places: places, parks: parks, visitedPlaces: visitedPlaces,
            visitedPlaceIDs: visitedPlaceIDs
        )
        nationalParksByCountry = byCountry.parks
        subdivisionsByCountry = byCountry.subdivisions
        regionsByCountry = byCountry.regions
        countries = Completion(
            visited: Set(visitedPlaces.map(\.country)).count,
            total: byCountry.parks.count
        )

        nearestUnvisited = Self.nearest(
            to: origin,
            among: parks.filter { !visitedPlaceIDs.contains($0.id) }
        )
    }

    // MARK: - Pieces

    /// The per-country figures, for each country with places in the data, in
    /// `Country.allCases` order: the US, then Japan, then Norway.
    private static func byCountry(
        places: [Place],
        parks: [Place],
        visitedPlaces: [Place],
        visitedPlaceIDs: Set<UnigridsID>
    ) -> CountryFigures {
        let present = Set(places.map(\.country))
        let countries = Country.allCases.filter(present.contains)
        let parks = countries.map { country in
            let mine = parks.filter { $0.country == country }
            return CountryCompletion(
                country: country,
                completion: Completion(
                    visited: mine.count { visitedPlaceIDs.contains($0.id) },
                    total: mine.count
                )
            )
        }
        let subdivisions = countries.map { country in
            let codes = Set(
                visitedPlaces.filter { $0.country == country }.flatMap(\.subdivisions).map(\.code)
            )
            let all = Subdivision.all(in: country)
            return CountryCompletion(
                country: country,
                completion: Completion(
                    visited: all.count { codes.contains($0.code) },
                    total: all.count
                )
            )
        }
        let visitedRegions = Set(visitedPlaces.map(\.resolvedPassportRegion))
        let regions = countries.map { country in
            let all = PassportRegion.regions(in: country)
            return CountryCompletion(
                country: country,
                completion: Completion(
                    visited: all.count { visitedRegions.contains($0) },
                    total: all.count
                )
            )
        }
        return CountryFigures(parks: parks, subdivisions: subdivisions, regions: regions)
    }

    private struct CountryFigures {
        let parks: [CountryCompletion]
        let subdivisions: [CountryCompletion]
        let regions: [CountryCompletion]
    }

    private static func states(in places: [Place]) -> [USState] {
        let codes = Set(places.flatMap { $0.states.map(\.code) })
        return USState.all.filter { codes.contains($0.code) }
    }

    private static func regions(in places: [Place]) -> [PassportRegion] {
        let visited = Set(places.map(\.resolvedPassportRegion))
        return PassportRegion.regions(in: .unitedStates).filter { visited.contains($0) }
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
            // A hike of a trail is the round trip, or once round a loop (`walkedMetres`).
            totals.distance += trail.walkedMetres * share
            totals.gain += (trail.climbMetres ?? 0) * share
            totals.longest = max(totals.longest, trail.walkedMetres * share)
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
