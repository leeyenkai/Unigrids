import Foundation
import SwiftData
import UnigridsCore
import UnigridsLog
import UnigridsReference

/// The weather on each logged visit, fetched once and kept (SPECIFICATION.md §11:
/// "Weather for each visit is fetched once when the visit is logged … and stored, so
/// stats never depend on a live call").
///
/// Runs when the app opens and whenever a visit is logged, a few visits at a time, for
/// visits whose day is over at the place and that have none; `WeatherBackfillPolicy`
/// decides which. Sends the park's coordinates and the date to Open-Meteo, nothing about
/// the reader (§15).
@MainActor
enum WeatherBackfill {
    private static var running = false
    private static var again = false
    private static let attemptsKey = "weather.attempts"

    /// Start a pass, or, if one is running, ask for another after it, so a visit logged
    /// mid-pass is not left until the next launch. Not tied to a view: a pass is not
    /// cancelled because the screen that started it changed.
    static func schedule(context: ModelContext, store: any ReferenceStore) {
        guard !running else {
            again = true
            return
        }
        running = true
        Task {
            repeat {
                again = false
                await pass(context: context, store: store)
            } while again
            running = false
        }
    }

    private static func pass(
        context: ModelContext,
        store: any ReferenceStore,
        limit: Int = 30
    ) async {
        let log = LogStore(context: context)
        guard let visits = try? log.visits() else { return }
        var attempts = loadAttempts()
        let due = visits
            .filter { visit in
                guard visit.weather == nil else { return false }
                let calendar = UnigridsCalendar.gregorian(at: store.place(visit.place))
                return WeatherBackfillPolicy.isDue(
                    date: visit.date, calendar: calendar, attempt: attempts[visit.id]
                )
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        for visit in due {
            guard let place = store.place(visit.place) else {
                // A place that left the dataset will never resolve.
                attempts[visit.id] = .init(count: WeatherBackfillPolicy.maxAttempts, last: Date())
                continue
            }
            let calendar = UnigridsCalendar.gregorian(at: place)
            guard let (day, recent) = await OpenMeteo.history(
                at: place.centre, on: visit.date, calendar: calendar
            ), day.highCelsius != nil || day.code != nil else {
                let count = (attempts[visit.id]?.count ?? 0) + 1
                attempts[visit.id] = .init(count: count, last: Date())
                continue
            }
            // The visit may have been deleted, or given weather, while the request was out.
            guard visit.modelContext != nil, !visit.isDeleted,
                  visit.weather == nil else { continue }
            let snapshot = WeatherSnapshot(
                date: visit.date,
                highCelsius: day.highCelsius,
                lowCelsius: day.lowCelsius,
                precipitationMillimetres: day.precipitationMillimetres,
                condition: day.condition?.name,
                source: recent ? .openMeteoRecent : .openMeteoArchive
            )
            try? log.attach(snapshot, to: visit)
            attempts[visit.id] = nil
        }
        saveAttempts(attempts)
    }

    private static func loadAttempts() -> [UUID: WeatherBackfillPolicy.Attempt] {
        guard let data = UserDefaults.standard.data(forKey: attemptsKey),
              let stored = try? JSONDecoder().decode(
                  [UUID: WeatherBackfillPolicy.Attempt].self, from: data
              )
        else { return [:] }
        return stored
    }

    private static func saveAttempts(_ attempts: [UUID: WeatherBackfillPolicy.Attempt]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(attempts), forKey: attemptsKey)
    }
}
