import Foundation
import Testing
@testable import UnigridsCore

@Suite("America 250 seal rule")
struct America250Tests {
    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let date = calendar.date(from: components) else {
            Issue.record("could not build \(year)-\(month)-\(day)")
            return Date()
        }
        return date
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test("a stamp dated in 2026 carries the seal")
    func sealInCommemorativeYear() {
        #expect(America250.applies(to: date(2026, 6, 15), calendar: utcCalendar))
    }

    @Test("the seal covers the whole calendar year, both ends")
    func sealCoversWholeYear() {
        #expect(America250.applies(to: date(2026, 1, 1), calendar: utcCalendar))
        #expect(America250.applies(to: date(2026, 12, 31), calendar: utcCalendar))
    }

    @Test("adjacent years do not carry the seal")
    func noSealOutsideTheYear() {
        #expect(!America250.applies(to: date(2025, 12, 31), calendar: utcCalendar))
        #expect(!America250.applies(to: date(2027, 1, 1), calendar: utcCalendar))
    }

    @Test("the rule follows the stamp's date, not when it was entered")
    func ruleFollowsStampDate() {
        // A 2026 visit logged in 2028 still earns the seal; a 2025 visit back-dated
        // during 2026 does not. The rule only ever sees the stamp's own date, which is
        // what makes both of those true.
        let backDated = date(2025, 7, 4)
        let lateEntered = date(2026, 7, 4)
        #expect(!America250.applies(to: backDated, calendar: utcCalendar))
        #expect(America250.applies(to: lateEntered, calendar: utcCalendar))
    }
}
