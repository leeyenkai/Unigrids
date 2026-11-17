import Foundation
import SwiftData
import UnigridsCore
import UnigridsLog
import UnigridsReference
import UserNotifications
#if os(iOS)
    import BackgroundTasks
#endif

/// Background alerts for parks on upcoming trips (SPECIFICATION.md §10): a look at the
/// NPS feed every few hours, and a notification when a new danger or closure is posted
/// at one of them.
///
/// Every trigger runs the same `run`: iOS's background app refresh, the app coming to the
/// front, and on the Mac a loop while the app is open. Without an NPS key in the build
/// there is no feed, and nothing runs. Notifications ask for provisional permission, so
/// they arrive quietly in Notification Center until the reader decides.
@MainActor
public enum AlertWatch {
    /// Also listed under `BGTaskSchedulerPermittedIdentifiers` in `App/Info.plist`.
    public static let taskID = "app.unigrids.alerts"
    static let seenKey = "alerts.watch.seen"
    static let prefix = "alert-"

    /// The park codes on trips under way, or starting within the next thirty days.
    static func parkCodes(trips: [Trip], store: any ReferenceStore, now: Date) -> Set<String> {
        let horizon = now.addingTimeInterval(30 * 86400)
        let soon = trips.filter { trip in
            switch trip.status(on: now) {
            case .active: true
            case .planned: trip.startDate.map { $0 <= horizon } ?? false
            case .done: false
            }
        }
        return Set(soon.flatMap(\.orderedStops).compactMap {
            store.place($0.place)?.npsParkCode?.lowercased()
        })
    }

    /// Whether there is anything to watch in this build: the NPS feed, given a key, or
    /// the warning services abroad, given parks there.
    static func isActive(store: any ReferenceStore) -> Bool {
        NPSAlerts.isConfigured || store.nationalParks.contains { $0.country != .unitedStates }
    }

    /// Look once: fetch the watched parks' alerts, notify what is new, remember the rest.
    public static func run(log: StoreLoader, store: any ReferenceStore) async {
        // Before the first unlock the log cannot be read; the next run will look.
        guard isActive(store: store), ProtectedData.isAvailable else { return }
        await log.load()
        guard let container = log.container else { return }
        let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
        await runAbroad(trips: trips, store: store)
        guard NPSAlerts.isConfigured else { return }
        let watching = parkCodes(trips: trips, store: store, now: Date())
        let seen = loadSeen()
        guard !watching.isEmpty else {
            save(AlertDiff.Seen(parks: [], alerts: seen.alerts))
            return
        }
        // The whole feed, filtered here: asking for the trip's parks by code would tell the
        // NPS where the reader is going.
        guard let alerts = try? await NPSAlerts.fetchAll().filter({
            $0.parkCode.map { watching.contains($0.lowercased()) } ?? false
        }) else { return }
        let byID = Dictionary(alerts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = AlertDiff.check(
            alerts.compactMap { alert in
                alert.parkCode.map {
                    AlertDiff.Alert(
                        id: alert.id,
                        parkCode: $0,
                        isUrgent: alert.kind == .danger || alert.kind == .closure
                    )
                }
            },
            watching: watching,
            seen: seen
        )
        save(result.seen)
        for item in result.notify {
            if let alert = byID[item.id] {
                await post(alert, store: store)
            }
        }
    }

    /// The parks abroad on trips under way or starting within thirty days.
    static func parksAbroad(trips: [Trip], store: any ReferenceStore, now: Date) -> [Place] {
        let horizon = now.addingTimeInterval(30 * 86400)
        let soon = trips.filter { trip in
            switch trip.status(on: now) {
            case .active: true
            case .planned: trip.startDate.map { $0 <= horizon } ?? false
            case .done: false
            }
        }
        let places = soon.flatMap(\.orderedStops).compactMap { store.place($0.place) }
            .filter { $0.country != .unitedStates && AlertsCenter.covers($0) }
        var seen = Set<UnigridsID>()
        return places.filter { seen.insert($0.id).inserted }
    }

    /// The same look for parks abroad, against JMA and Varsom, remembered apart from the
    /// NPS's so neither can make the other's alerts look new. A service that cannot be
    /// reached leaves what was seen as it was.
    private static func runAbroad(trips: [Trip], store: any ReferenceStore) async {
        let parks = parksAbroad(trips: trips, store: store, now: Date())
        let seen = loadSeen(key: seenAbroadKey)
        guard !parks.isEmpty else {
            save(AlertDiff.Seen(parks: [], alerts: seen.alerts), key: seenAbroadKey)
            return
        }
        let center = AlertsCenter()
        let japan = parks.filter { $0.country == .japan }
        await center.refreshJapan(japan.map { ($0, store.boundary(for: $0.id)) }, force: true)
        for park in parks where park.country == .norway {
            await center.refreshAbroad(park, boundary: nil)
        }
        let reached = parks.filter { !center.failed(for: $0) }
        guard !reached.isEmpty else { return }
        var byID: [String: (ParkAlert, Place)] = [:]
        let alerts = reached.flatMap { park in
            center.alerts(for: park).map { alert in
                byID[alert.id] = (alert, park)
                return AlertDiff.Alert(
                    id: alert.id,
                    parkCode: park.id.rawValue,
                    isUrgent: alert.kind == .danger || alert.kind == .closure
                )
            }
        }
        let result = AlertDiff.check(
            alerts,
            watching: Set(reached.map(\.id.rawValue)),
            unreached: Set(parks.filter { center.failed(for: $0) }.map(\.id.rawValue)),
            seen: seen
        )
        save(result.seen, key: seenAbroadKey)
        for item in result.notify {
            if let (alert, park) = byID[item.id] {
                await post(alert, at: park)
            }
        }
    }

    private static func post(_ alert: ParkAlert, at place: Place) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
        let content = UNMutableNotificationContent()
        content.title = "\(alert.kind.name) at \(place.name)"
        content.body = alert.title
        content.sound = .default
        content.userInfo = [
            NotificationRoute.key: NotificationRoute.alert.rawValue,
            "place": place.id.rawValue,
        ]
        let request = UNNotificationRequest(
            identifier: prefix + alert.id, content: content, trigger: nil
        )
        try? await center.add(request)
    }

    private static func post(_ alert: ParkAlert, store: any ReferenceStore) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .provisional])
        let place = store.places.first {
            $0.npsParkCode?.lowercased() == alert.parkCode?.lowercased()
        }
        let content = UNMutableNotificationContent()
        content.title = "\(alert.kind.name) at \(place?.name ?? "a park on your trip")"
        content.body = alert.title
        content.sound = .default
        var info: [String: String] = [NotificationRoute.key: NotificationRoute.alert.rawValue]
        info["place"] = place?.id.rawValue
        content.userInfo = info
        let request = UNNotificationRequest(
            identifier: prefix + alert.id, content: content, trigger: nil
        )
        try? await center.add(request)
    }

    /// Parks abroad keep their own record, keyed by place identifier.
    static let seenAbroadKey = "alerts.watch.seen.abroad"

    private static func loadSeen(key: String = seenKey) -> AlertDiff.Seen {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(AlertDiff.Seen.self, from: $0) } ?? AlertDiff
            .Seen()
    }

    private static func save(_ seen: AlertDiff.Seen, key: String = seenKey) {
        UserDefaults.standard.set(try? JSONEncoder().encode(seen), forKey: key)
    }

    #if os(iOS)
        /// Ask iOS to wake the app to look again in a few hours. iOS decides when, or
        /// whether: background refresh is a request, not a timer.
        public static func schedule(store: any ReferenceStore) async {
            guard isActive(store: store) else { return }
            let request = BGAppRefreshTaskRequest(identifier: taskID)
            request.earliestBeginDate = Date().addingTimeInterval(3 * 3600)
            try? await BGTaskScheduler.shared.submitTaskRequest(request)
        }
    #else
        /// Look every three hours while the app is open.
        public static func keepWatching(log: StoreLoader, store: any ReferenceStore) async {
            guard isActive(store: store) else { return }
            while !Task.isCancelled {
                await run(log: log, store: store)
                try? await Task.sleep(for: .seconds(3 * 3600))
            }
        }
    #endif
}
