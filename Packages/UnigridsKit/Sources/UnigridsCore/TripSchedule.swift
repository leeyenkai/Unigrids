import Foundation

/// A drive between two consecutive stops, as MapKit's directions measured it.
public struct DriveLeg: Hashable, Sendable {
    public let from: UnigridsID
    public let to: UnigridsID
    public let seconds: Double
    public let metres: Double

    public init(from: UnigridsID, to: UnigridsID, seconds: Double, metres: Double) {
        self.from = from
        self.to = to
        self.seconds = seconds
        self.metres = metres
    }
}

/// One day of a trip: its stops and how long the driving into them takes
/// (SPECIFICATION.md §10, "a day total and a warning when a day looks overloaded").
public struct TripDay: Hashable, Sendable, Identifiable {
    public let day: Date
    public let stopIDs: [UnigridsID]
    public let drivingSeconds: Double
    public let drivingMetres: Double

    public var id: Date {
        day
    }

    /// Whether the day's driving passes `TripSchedule.longDaySeconds`.
    public var isLong: Bool {
        drivingSeconds > TripSchedule.longDaySeconds
    }
}

public enum TripSchedule {
    /// Six hours at the wheel: past this a day with parks in it has no time for the parks.
    public static let longDaySeconds: Double = 6 * 3600

    /// The trip's dated days in order, each with the driving that arrives on it.
    ///
    /// A leg belongs to the day of the stop it arrives at, because that is the day the
    /// driving happens on. Stops without a date are left out of the days and their legs
    /// uncounted, rather than guessed onto a day.
    public static func days(
        stops: [(id: UnigridsID, date: Date?)],
        legs: [DriveLeg],
        calendar: Calendar = .current
    ) -> [TripDay] {
        var order: [Date] = []
        var stopsByDay: [Date: [UnigridsID]] = [:]
        var seconds: [Date: Double] = [:]
        var metres: [Date: Double] = [:]
        let legsByArrival = Dictionary(
            legs.map { ($0.to, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (index, stop) in stops.enumerated() {
            guard let date = stop.date else { continue }
            let day = calendar.startOfDay(for: date)
            if stopsByDay[day] == nil {
                order.append(day)
            }
            stopsByDay[day, default: []].append(stop.id)
            // The first stop has nothing driven into it on the trip.
            if index > 0, let leg = legsByArrival[stop.id], leg.from == stops[index - 1].id {
                seconds[day, default: 0] += leg.seconds
                metres[day, default: 0] += leg.metres
            }
        }
        return order.sorted().map { day in
            TripDay(
                day: day,
                stopIDs: stopsByDay[day] ?? [],
                drivingSeconds: seconds[day] ?? 0,
                drivingMetres: metres[day] ?? 0
            )
        }
    }

    /// Whether a date falls in the months when mountain roads and high facilities close —
    /// November to April in the northern hemisphere — so a guide's seasonal-closure notes
    /// are worth raising on a stop planned then.
    public static func isClosureSeason(_ date: Date, calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        return month >= 11 || month <= 4
    }
}
