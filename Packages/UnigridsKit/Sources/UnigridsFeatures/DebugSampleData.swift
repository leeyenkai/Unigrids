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
            // Abroad (0.10.0): a 2026 stamp in Japan shows the book's face, and no America
            // 250 seal; Svalbard checks the far north.
            Sample("jp-np-shiretoko", past(2026, 8, 3), [21, 13, 2], "Showers"),
            Sample("jp-np-fuji-hakone-izu", past(2025, 7, 20), [27, 21, 8], "Rain"),
            Sample("no-np-jotunheimen", past(2026, 7, 15), [14, 5, 1], "Clear"),
            Sample("no-np-rondane", past(2026, 7, 18), [17, 6, 0], "Clear"),
            Sample("no-np-nordvest-spitsbergen", past(2025, 6, 10), [4, 0, 0], "Clear"),
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
            // Planned for noon in Utah, as the stop sheet stores a day, so a stop reads as
            // the same day there as the trip's dates do here.
            let utah = UnigridsCalendar
                .gregorian(TimeZone(identifier: "America/Denver") ?? .current)
            for (place, offset) in stops {
                let date = UnigridsCalendar.noon(onDayOf: day(offset), shownIn: calendar, in: utah)
                _ = try? log.addStop(place, to: trip, on: date)
            }
            let reminder = Reminder(
                kind: .permit,
                date: day(2),
                title: "Angels Landing day-before lottery",
                url: URL(string: "https://www.recreation.gov/"),
                trip: trip
            )
            container.mainContext.insert(reminder)

            // A trip abroad in planning, for its flags, forecasts and warnings.
            if let norway = try? log.createTrip(
                name: "Jotunheimen and Rondane",
                startDate: day(30),
                endDate: day(34)
            ) {
                let oslo = UnigridsCalendar
                    .gregorian(TimeZone(identifier: "Europe/Oslo") ?? .current)
                for (place, offset) in [("no-np-jotunheimen", 30), ("no-np-rondane", 33)] {
                    let date = UnigridsCalendar.noon(
                        onDayOf: day(offset), shownIn: calendar, in: oslo
                    )
                    _ = try? log.addStop(UnigridsID(place), to: norway, on: date)
                }
            }

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
