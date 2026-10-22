import Foundation
import Testing
@testable import UnigridsCore

@Suite("Stats")
struct StatsTests {
    private func place(
        _ id: String,
        name: String,
        states: [String],
        lat: Double = 40,
        lon: Double = -100,
        kind: PlaceKind = .nationalPark,
        themes: [UnigridsID] = []
    ) -> Place {
        Place(
            id: UnigridsID(id),
            name: name,
            designation: "National Park",
            kind: kind,
            states: states.compactMap(USState.named),
            centre: Coordinate(latitude: lat, longitude: lon),
            themes: themes
        )
    }

    private func date(_ year: Int, _ month: Int = 6) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 15
        components.hour = 12
        return calendar.date(from: components) ?? Date()
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test("completion counts parks, not visits")
    func completionCountsDistinctParks() {
        let places = [
            place("np-a", name: "A", states: ["UT"]),
            place("np-b", name: "B", states: ["ME"]),
            place("np-c", name: "C", states: ["WY"]),
        ]
        // Three visits, but two of them are the same park.
        let visits = [
            VisitSummary(placeID: "np-a", date: date(2024)),
            VisitSummary(placeID: "np-a", date: date(2025)),
            VisitSummary(placeID: "np-b", date: date(2025)),
        ]
        let report = StatsReport(places: places, visits: visits, calendar: utcCalendar)
        #expect(report.nationalParks == Completion(visited: 2, total: 3))
        #expect(report.totalVisits == 3)
    }

    @Test("a park in two states credits both")
    func statesSpanParkBoundaries() {
        let places = [place("np-grsm", name: "Smokies", states: ["TN", "NC"])]
        let visits = [VisitSummary(placeID: "np-grsm", date: date(2026))]
        let report = StatsReport(places: places, visits: visits, calendar: utcCalendar)
        #expect(report.visitedStates.map(\.code).sorted() == ["NC", "TN"])
    }

    @Test("a visit to a place outside the dataset still counts as a visit")
    func unresolvedPlaceDoesNotBreakStats() {
        // Reference data is replaced wholesale on each release, so a stored visit can
        // outlive its place. It must not vanish and must not crash the stats.
        let places = [place("np-a", name: "A", states: ["UT"])]
        let visits = [
            VisitSummary(placeID: "np-a", date: date(2025)),
            VisitSummary(placeID: "np-gone", date: date(2025)),
        ]
        let report = StatsReport(places: places, visits: visits, calendar: utcCalendar)
        #expect(report.totalVisits == 2)
        #expect(report.nationalParks == Completion(visited: 1, total: 1))
    }

    @Test("visits group by year, ascending")
    func visitsByYear() {
        let places = [place("np-a", name: "A", states: ["UT"])]
        let visits = [
            VisitSummary(placeID: "np-a", date: date(2026)),
            VisitSummary(placeID: "np-a", date: date(2024)),
            VisitSummary(placeID: "np-a", date: date(2026)),
        ]
        let report = StatsReport(places: places, visits: visits, calendar: utcCalendar)
        #expect(report.visitsByYear.map(\.year) == [2024, 2026])
        #expect(report.visitsByYear.map(\.count) == [1, 2])
    }

    @Test("seasons come from the visit month")
    func visitsBySeason() {
        let places = [place("np-a", name: "A", states: ["UT"])]
        let visits = [
            VisitSummary(placeID: "np-a", date: date(2025, 1)),
            VisitSummary(placeID: "np-a", date: date(2025, 7)),
            VisitSummary(placeID: "np-a", date: date(2025, 8)),
        ]
        let report = StatsReport(places: places, visits: visits, calendar: utcCalendar)
        let counts = Dictionary(
            uniqueKeysWithValues: report.visitsBySeason.map { ($0.season, $0.count) }
        )
        #expect(counts[.winter] == 1)
        #expect(counts[.summer] == 2)
        #expect(counts[.spring] == 0)
    }

    @Test("theme progress only reports themes some park carries")
    func themeProgress() {
        let volcanoes = Theme(id: "theme-volcanoes", family: .geology, name: "Volcanoes")
        let caves = Theme(id: "theme-caves", family: .geology, name: "Caves")
        let places = [
            place(
                "np-havo",
                name: "Hawaii Volcanoes",
                states: ["HI"],
                themes: ["theme-volcanoes"]
            ),
            place("np-lavo", name: "Lassen", states: ["CA"], themes: ["theme-volcanoes"]),
            place("np-zion", name: "Zion", states: ["UT"]),
        ]
        let visits = [VisitSummary(placeID: "np-havo", date: date(2025))]
        let report = StatsReport(
            places: places,
            visits: visits,
            themes: [volcanoes, caves],
            calendar: utcCalendar
        )
        #expect(report.themeProgress.count == 1)
        #expect(report.themeProgress.first?.completion == Completion(visited: 1, total: 2))
    }

    @Test("a partial hike counts half, and claims no high point")
    func partialHikesCountHalf() {
        let trail = Trail(
            id: "trail-x",
            placeID: "np-a",
            name: "X",
            lengthMetres: 10000,
            gainMetres: 1000,
            lossMetres: 1000,
            highPointMetres: 2500,
            difficulty: .strenuous,
            routeType: .outAndBack
        )
        let full = StatsReport(
            places: [],
            visits: [],
            hikes: [HikeSummary(trailID: "trail-x", date: date(2025), completion: .full)],
            trails: [trail],
            calendar: utcCalendar
        )
        let partial = StatsReport(
            places: [],
            visits: [],
            hikes: [HikeSummary(trailID: "trail-x", date: date(2025), completion: .partial)],
            trails: [trail],
            calendar: utcCalendar
        )
        // An out-and-back trail is hiked there and back: twice its length, and its rise
        // plus its fall in climbing.
        #expect(full.distanceHikedMetres == 20000)
        #expect(full.elevationGainedMetres == 2000)
        #expect(full.highestPointMetres == 2500)
        #expect(partial.distanceHikedMetres == 10000)
        #expect(partial.elevationGainedMetres == 1000)
        // The app does not know where the walker turned back, so it must not claim the
        // summit was reached.
        #expect(partial.highestPointMetres == nil)
    }

    @Test("the nearest unvisited park skips the ones already visited")
    func nearestUnvisited() {
        let places = [
            place("np-near", name: "Near", states: ["UT"], lat: 40.1, lon: -100),
            place("np-far", name: "Far", states: ["ME"], lat: 45, lon: -100),
        ]
        let visits = [VisitSummary(placeID: "np-near", date: date(2025))]
        let report = StatsReport(
            places: places,
            visits: visits,
            origin: Coordinate(latitude: 40, longitude: -100),
            calendar: utcCalendar
        )
        #expect(report.nearestUnvisited?.place.id == "np-far")
    }

    @Test("an empty log reports zero, not a division by zero")
    func emptyLog() {
        let report = StatsReport(places: [], visits: [], calendar: utcCalendar)
        #expect(report.nationalParks.fraction == 0)
        #expect(report.firstVisit == nil)
        #expect(report.everestsClimbed == 0)
    }
}
