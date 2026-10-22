import Foundation
import Testing
@testable import UnigridsCore

@Suite("Streaks and the year in review")
struct YearInReviewTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    private func visit(_ place: UnigridsID, _ date: Date) -> VisitSummary {
        VisitSummary(placeID: place, date: date)
    }

    private func state(_ code: String) -> [USState] {
        USState.all.filter { $0.code == code }
    }

    @Test("the longest run of months, and the run still going")
    func monthRuns() {
        let visits = [
            visit("a", day(2025, 3)), visit("a", day(2025, 4)), visit("b", day(2025, 4, 2)),
            visit("a", day(2025, 5)), visit("a", day(2025, 8)), visit("a", day(2025, 9)),
        ]
        let result = Streaks.months(visits, now: day(2025, 10), calendar: calendar)
        #expect(result.longest?.count == 3)
        #expect(result.longest?.first == calendar.date(from: DateComponents(year: 2025, month: 3)))
        // September's run is still going in October; a gap of a month more ends it.
        #expect(result.current?.count == 2)
        #expect(Streaks.months(visits, now: day(2025, 11), calendar: calendar).current == nil)
    }

    @Test("years in a row cross December into January")
    func yearRuns() {
        let visits = [
            visit("a", day(2023, 12, 31)),
            visit("a", day(2024, 1, 1)),
            visit("a", day(2026, 6)),
        ]
        let result = Streaks.years(visits, now: day(2026, 7), calendar: calendar)
        #expect(result.longest?.count == 2)
        #expect(result.current?.count == 1)
        #expect(Streaks.years([], calendar: calendar).longest == nil)
    }

    @Test("a year counts new places and new national parks only the first time")
    func review() {
        let places = [
            Place(
                id: "np-zion",
                name: "Zion",
                designation: "National Park",
                kind: .nationalPark,
                states: state("UT"),
                centre: Coordinate(latitude: 37.2, longitude: -113)
            ),
            Place(
                id: "np-arches",
                name: "Arches",
                designation: "National Park",
                kind: .nationalPark,
                states: state("UT"),
                centre: Coordinate(latitude: 38.7, longitude: -109.6)
            ),
            Place(
                id: "sp-nv-valley-of-fire",
                name: "Valley of Fire",
                designation: "State Park",
                kind: .statePark,
                states: state("NV"),
                centre: Coordinate(latitude: 36.4, longitude: -114.5)
            ),
        ]
        let visits = [
            visit("np-zion", day(2025, 5)),
            visit("np-zion", day(2026, 4)), visit("np-arches", day(2026, 4, 20)),
            visit("sp-nv-valley-of-fire", day(2026, 9)),
        ]
        let year = YearInReview(year: 2026, places: places, visits: visits, calendar: calendar)
        #expect(year.visits == 3)
        #expect(year.places == 3)
        #expect(year.firstTimePlaces == 2)
        #expect(year.nationalParks == ["np-arches", "np-zion"])
        #expect(year.newNationalParks == ["np-arches"])
        #expect(year.states.map(\.code) == ["NV", "UT"])
        #expect(year.busiestMonth == 4)
        #expect(year.firstVisit?.placeID == "np-zion")
        #expect(YearInReview.years(in: visits, calendar: calendar) == [2026, 2025])
    }

    @Test("a year's hikes count by the Stats rule: a partial hike is half")
    func hikes() {
        let trail = Trail(
            id: "t",
            placeID: "np-zion",
            name: "T",
            lengthMetres: 5000,
            routeType: .loop
        )
        let hikes = [
            HikeSummary(trailID: "t", date: day(2026, 4), completion: .full),
            HikeSummary(trailID: "t", date: day(2026, 5), completion: .partial),
            HikeSummary(trailID: "t", date: day(2025, 5), completion: .full),
        ]
        let year = YearInReview(
            year: 2026, places: [], visits: [], hikes: hikes, trails: [trail], calendar: calendar
        )
        #expect(year.hikedMetres == 7500)
        #expect(year.trailsHiked == 1)
    }
}
