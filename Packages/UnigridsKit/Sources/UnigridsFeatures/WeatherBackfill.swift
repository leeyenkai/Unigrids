import Foundation
import SwiftData
import UnigridsCore
import UnigridsLog
import UnigridsReference

/// The weather on each logged visit, fetched once and kept (SPECIFICATION.md §11:
/// "Weather for each visit is fetched once when the visit is logged … and stored, so
/// stats never depend on a live call").
///
/// Runs when the app opens, a few visits at a time, for visits that have none. Sends the
/// park's coordinates and the date to Open-Meteo; nothing about the reader (§15).
@MainActor
enum WeatherBackfill {
    private static var running = false

    static func run(context: ModelContext, store: any ReferenceStore, limit: Int = 30) async {
        guard !running else { return }
        running = true
        defer { running = false }
        let log = LogStore(context: context)
        guard let visits = try? log.visits() else { return }
        let pending = visits
            .filter { $0.weather == nil && $0.date < Date() }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        for visit in pending {
            guard let place = store.place(visit.place),
                  let (day, recent) = await OpenMeteo.history(at: place.centre, on: visit.date),
                  day.highCelsius != nil || day.code != nil
            else { continue }
            // The visit may have been deleted while the request was out.
            guard visit.modelContext != nil, visit.weather == nil else { continue }
            let snapshot = WeatherSnapshot(
                date: visit.date,
                highCelsius: day.highCelsius,
                lowCelsius: day.lowCelsius,
                precipitationMillimetres: day.precipitationMillimetres,
                condition: day.condition?.name,
                source: recent ? .openMeteoRecent : .openMeteoArchive
            )
            context.insert(snapshot)
            try? log.attach(snapshot, to: visit)
        }
    }
}
