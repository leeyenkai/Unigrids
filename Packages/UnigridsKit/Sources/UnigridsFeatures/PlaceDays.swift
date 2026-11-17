import Foundation
import UnigridsCore
import UnigridsLog
import UnigridsReference

// Log entries as the counting screens see them: each on its place's own day, in the
// reader's calendar (ADR 0012). Stats, streaks and Year in review reckon in the reader's
// calendar; a visit's date is noon at its place, which can be another day there.

extension ReferenceStore {
    /// Visits re-dated onto their places' own days.
    func placeDaySummaries(
        _ visits: [Visit],
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> [VisitSummary] {
        var calendars: [UnigridsID: Calendar] = [:]
        return visits.map { visit in
            let id = visit.place
            let own = calendars[id] ?? UnigridsCalendar.gregorian(at: place(id), id: id)
            calendars[id] = own
            return visit.summary.onPlaceDay(own, in: calendar)
        }
    }

    /// Hikes re-dated onto their parks' own days.
    func placeDaySummaries(
        _ hikes: [Hike],
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> [HikeSummary] {
        guard !hikes.isEmpty else { return [] }
        let parks = Dictionary(
            allTrails.map { ($0.id, $0.placeID) },
            uniquingKeysWith: { first, _ in first }
        )
        var calendars: [UnigridsID: Calendar] = [:]
        return hikes.map { hike in
            let summary = hike.summary
            guard let park = parks[summary.trailID] else { return summary }
            let own = calendars[park] ?? UnigridsCalendar.gregorian(at: place(park), id: park)
            calendars[park] = own
            return summary.onPlaceDay(own, in: calendar)
        }
    }
}
