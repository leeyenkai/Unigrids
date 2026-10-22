import Foundation
import Testing
import UnigridsCore

@Suite("Calendar days")
struct UnigridsCalendarTests {
    private func date(_ text: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: text))
    }

    @Test("the America 250 rule does not depend on the device's calendar system")
    func nonGregorianDevice() throws {
        let stamp = try date("2026-07-04T18:00:00Z")
        // What `Calendar.current` is on a phone set to the Buddhist or Japanese calendar.
        let buddhist = Calendar(identifier: .buddhist)
        let japanese = Calendar(identifier: .japanese)
        #expect(buddhist.component(.year, from: stamp) == 2569)
        #expect(japanese.component(.year, from: stamp) == 8)
        // The rules no longer read it.
        #expect(America250.applies(to: stamp))
        #expect(America250.applies(to: stamp, calendar: UnigridsCalendar.gregorian()))
    }

    @Test("a stamp's day is the day where it was made, wherever it is read")
    func dayAtThePlace() throws {
        // 00:30 on New Year's Day 2026 in New York is 21:30 on New Year's Eve in Los Angeles.
        let stamp = try date("2026-01-01T05:30:00Z")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(America250.applies(to: stamp, calendar: UnigridsCalendar.gregorian(newYork)))
        #expect(!America250.applies(to: stamp, calendar: UnigridsCalendar.gregorian(losAngeles)))
        #expect(UnigridsCalendar.dayKey(stamp, calendar: UnigridsCalendar.gregorian(newYork))
            == "2026-01-01")
    }

    @Test("a picked day is stored as noon at the place, and reads as that day nearby")
    func noonAtThePlace() throws {
        let guam = try #require(TimeZone(identifier: "Pacific/Guam"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        // Picked on a phone in New York at 22:00 on 3 March: the user means 3 March.
        let picked = try date("2026-03-04T03:00:00Z")
        let stored = UnigridsCalendar.noon(
            onDayOf: picked,
            shownIn: UnigridsCalendar.gregorian(newYork),
            in: UnigridsCalendar.gregorian(guam)
        )
        #expect(UnigridsCalendar.dayKey(stored, calendar: UnigridsCalendar.gregorian(guam))
            == "2026-03-03")
        #expect(UnigridsCalendar.gregorian(guam).component(.hour, from: stored) == 12)
    }

    @Test("a place keeps its own zone, then its state's, then the device's")
    func zoneFallback() throws {
        let navajo = Place(
            id: "nps-nava", name: "Navajo", designation: "National Monument", kind: .npsUnit,
            states: [try #require(USState.named("AZ"))],
            centre: Coordinate(latitude: 36.7, longitude: -110.5),
            timeZoneID: "America/Denver"
        )
        #expect(UnigridsCalendar.timeZone(for: navajo).identifier == "America/Denver")
        let unzoned = Place(
            id: "sp-x", name: "X", designation: "State Park", kind: .statePark,
            states: [try #require(USState.named("AZ"))],
            centre: Coordinate(latitude: 33, longitude: -112)
        )
        #expect(UnigridsCalendar.timeZone(for: unzoned).identifier == "America/Phoenix")
        #expect(UnigridsCalendar.timeZone(for: nil) == TimeZone.current)
    }

    @Test("every state and territory names a zone the system knows")
    func stateZonesResolve() {
        for state in USState.all {
            #expect(state.mainTimeZone != nil, "\(state.code)")
        }
    }

    @Test("a place's time zone decodes, and its absence is not an error")
    func decoding() throws {
        let json = Data(#"""
        [{"id": "np-zion", "name": "Zion", "kind": "nationalPark",
          "centre": {"latitude": 37.3, "longitude": -113.0}, "timeZoneID": "America/Denver",
          "visitation": {"monthly": [1,2,3,4,5,6,7,8,9,10,11,12], "years": [2022, 2025]}},
         {"id": "sp-x", "name": "X", "kind": "statePark",
          "centre": {"latitude": 33, "longitude": -112},
          "visitation": {"monthly": "broken"}}]
        """#.utf8)
        let places = try JSONDecoder().decode([Place].self, from: json)
        #expect(places[0].timeZoneID == "America/Denver")
        #expect(places[0].visitation?.busiestMonth == 12)
        #expect(places[0].visitation?.yearsDescription == "2022–2025")
        #expect(places[1].timeZoneID == nil)
        #expect(places[1].visitation == nil)
    }
}
