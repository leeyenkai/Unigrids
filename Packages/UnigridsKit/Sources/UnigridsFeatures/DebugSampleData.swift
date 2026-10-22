import Foundation
import SwiftData
import UnigridsCore
import UnigridsLog

/// A sample log for checking screens by screenshot: a trip in planning, visits with
/// weather, stamps and hikes. Debug builds only, and only into an in-memory store, so it
/// can never reach a real log.
public enum DebugSampleData {
    /// Whether the app was launched with `-UnigridsDebugSampleData YES`.
    public static var isRequested: Bool {
        #if DEBUG
            UserDefaults.standard.bool(forKey: "UnigridsDebugSampleData")
        #else
            false
        #endif
    }

    private struct Sample {
        let place: UnigridsID
        let date: Date
        /// High, low and precipitation.
        let weather: [Double]
        let condition: String

        init(_ place: UnigridsID, _ date: Date, _ weather: [Double], _ condition: String) {
            self.place = place
            self.date = date
            self.weather = weather
            self.condition = condition
        }
    }

    private static func samples(past: (Int, Int, Int) -> Date) -> [Sample] {
        [
            Sample("np-acadia", past(2025, 9, 14), [19, 9, 0], "Clear"),
            Sample("np-yellowstone", past(2024, 6, 20), [22, 3, 4], "Showers"),
            Sample("np-grand-teton", past(2024, 6, 22), [24, 6, 0], "Clear"),
            Sample("np-glacier", past(2024, 6, 25), [18, 7, 12], "Rain"),
            Sample("np-death-valley", past(2023, 7, 3), [47, 33, 0], "Clear"),
            Sample("np-rocky-mountain", past(2023, 12, 28), [-4, -15, 6], "Snow"),
            Sample("nps-stli", past(2026, 4, 2), [14, 6, 0], "Clear"),
            Sample("nf-white-river", past(2023, 12, 27), [-6, -18, 3], "Snow"),
        ]
    }

    @MainActor
    private static func logVisit(_ sample: Sample, log: LogStore, container: ModelContainer) {
        guard let visit = try? log.checkIn(to: sample.place, on: sample.date) else { return }
        let snapshot = WeatherSnapshot(
            date: sample.date, highCelsius: sample.weather[0], lowCelsius: sample.weather[1],
            precipitationMillimetres: sample.weather[2], condition: sample.condition,
            source: .openMeteoArchive
        )
        container.mainContext.insert(snapshot)
        try? log.attach(snapshot, to: visit)
        _ = try? log.stamp(sample.place, on: sample.date)
    }

    /// Fill an in-memory container with the sample log.
    @MainActor
    public static func seed(_ container: ModelContainer) {
        #if DEBUG
            let log = LogStore(context: container.mainContext)
            let calendar = Calendar.current
            func day(_ offset: Int) -> Date {
                calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date()))?
                    .addingTimeInterval(10 * 3600) ?? Date()
            }
            func past(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
                calendar.date(from: DateComponents(
                    year: year,
                    month: month,
                    day: dayOfMonth,
                    hour: 11
                ))
                    ?? Date()
            }
            guard let trip = try? log.createTrip(
                name: "Utah's Mighty Five",
                startDate: day(4),
                endDate: day(8)
            ) else { return }
            let stops: [(UnigridsID, Int)] = [
                ("np-zion", 4), ("np-bryce-canyon", 5), ("np-capitol-reef", 6), ("np-arches", 7),
                ("np-canyonlands", 8),
            ]
            for (place, offset) in stops {
                _ = try? log.addStop(place, to: trip, on: day(offset))
            }
            let reminder = Reminder(
                kind: .permit,
                date: day(2),
                title: "Angels Landing day-before lottery",
                url: URL(string: "https://www.recreation.gov/"),
                trip: trip
            )
            container.mainContext.insert(reminder)

            for sample in samples(past: past) {
                logVisit(sample, log: log, container: container)
            }
            _ = try? log.markHiked(
                "trail-glacier-highline",
                in: "np-glacier",
                on: past(2024, 6, 25)
            )
            _ = try? log.markHiked(
                "trail-acadia-precipice-trail",
                in: "np-acadia",
                on: past(2025, 9, 14)
            )
        #endif
    }
}
