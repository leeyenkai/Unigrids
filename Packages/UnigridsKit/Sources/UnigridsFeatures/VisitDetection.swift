import CoreLocation
import Foundation
import Observation
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference
import UserNotifications

// Auto-detected visits (SPECIFICATION.md §9): with Always location permission, the app
// watches the outlines of the places nearest the reader and suggests a visit on arrival —
// "Looks like you're in Zion. Log a visit?" iOS lets an app watch twenty regions at once,
// so the watched set is the nearest nineteen places plus a ring around where the reader
// is, and leaving the ring re-plans the set. Everything happens on the device; no
// location is stored except the place and day of a suggestion the reader has not yet
// answered (§15).

/// Visits the device noticed and the reader has not yet answered.
@MainActor
@Observable
public final class DetectedVisits {
    public struct Suggestion: Codable, Hashable, Identifiable, Sendable {
        public let placeID: String
        public let date: Date

        public var id: String {
            "\(placeID)@\(Int(date.timeIntervalSince1970))"
        }
    }

    public private(set) var pending: [Suggestion]
    private let defaults: UserDefaults
    private static let key = "visits.detected"
    static let enabledKey = "visits.autoDetect"
    /// Whether the saved list has been read. Before the device's first unlock it reads as
    /// empty, and saving then would overwrite the real one; arrivals noticed meanwhile are
    /// kept in memory and merged in once it can be read.
    private var loaded = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pending = []
        if ProtectedData.isAvailable {
            pending = stored()
            loaded = true
            pruneStale()
        } else {
            Task { await loadWhenAvailable() }
        }
    }

    private func stored() -> [Suggestion] {
        defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Suggestion].self, from: $0) } ?? []
    }

    private func loadWhenAvailable() async {
        await ProtectedData.available()
        let noticed = pending
        pending = stored()
        loaded = true
        for suggestion in noticed where !pending.contains(suggestion) {
            pending.append(suggestion)
        }
        if !noticed.isEmpty {
            save()
        }
    }

    /// Note an arrival, once per place per day.
    func add(
        _ placeID: UnigridsID,
        at date: Date,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> Bool {
        guard !pending.contains(where: {
            $0.placeID == placeID.rawValue
                && UnigridsCalendar.isSameDay($0.date, date, calendar: calendar)
        }) else { return false }
        pending.append(Suggestion(placeID: placeID.rawValue, date: date))
        pruneStale()
        save()
        return true
    }

    /// A week-old suggestion is a visit the reader chose not to log.
    private func pruneStale() {
        pending.removeAll { Date().timeIntervalSince($0.date) > 7 * 86400 }
    }

    /// The suggestions not yet answered by a visit logged at the place that day, there.
    static func unanswered(
        _ pending: [Suggestion],
        visits: [Visit],
        store: any ReferenceStore
    ) -> [Suggestion] {
        pending.filter { suggestion in
            let calendar = UnigridsCalendar
                .gregorian(at: store.place(UnigridsID(suggestion.placeID)))
            return !visits.contains {
                $0.placeID == suggestion.placeID
                    && UnigridsCalendar.isSameDay($0.date, suggestion.date, calendar: calendar)
            }
        }
    }

    func dismiss(_ suggestion: Suggestion) {
        pending.removeAll { $0 == suggestion }
        save()
    }

    private func save() {
        guard loaded else { return }
        defaults.set(try? JSONEncoder().encode(pending), forKey: Self.key)
    }
}

extension AppServices {
    public static let detected = DetectedVisits()
}

#if os(iOS)
    /// Watches the nearest places' outlines while the reader allows it.
    @MainActor
    public enum VisitDetection {
        private static let monitorName = "unigrids.visits"
        private static let homeID = "home"
        private static let homeRadius: CLLocationDistance = 30000
        private static var listening: Task<Void, Never>?
        /// One monitor, opened once: Core Location expects one open monitor per name, and a
        /// second opened while a cancelled listener's was still alive split the events.
        private static var opened: CLMonitor?

        private static func monitor() async -> CLMonitor {
            if let opened {
                return opened
            }
            let monitor = await CLMonitor(monitorName)
            opened = monitor
            return monitor
        }

        public static var isEnabled: Bool {
            UserDefaults.standard.bool(forKey: DetectedVisits.enabledKey)
        }

        /// Start listening again at launch — including a launch iOS makes in the background
        /// to deliver an arrival — if the reader has turned detection on.
        public static func resume(store: any ReferenceStore) {
            guard listening == nil else { return }
            // Before the first unlock the setting reads as off whatever it is; wait to read
            // it rather than conclude the reader turned detection off.
            listening = Task {
                await ProtectedData.available()
                guard isEnabled else {
                    listening = nil
                    return
                }
                await listen(store: store)
            }
        }

        /// Turn detection on: ask for Always permission and notifications, then watch.
        static func enable(store: any ReferenceStore) async -> Bool {
            let granted = await LocationPermission.requestAlways()
            guard granted else { return false }
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            UserDefaults.standard.set(true, forKey: DetectedVisits.enabledKey)
            listening?.cancel()
            listening = Task { await listen(store: store, replan: true) }
            return true
        }

        static func disable() async {
            UserDefaults.standard.set(false, forKey: DetectedVisits.enabledKey)
            listening?.cancel()
            listening = nil
            let monitor = await monitor()
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
        }

        private static func listen(store: any ReferenceStore, replan: Bool = false) async {
            let monitor = await monitor()
            let watched = await monitor.identifiers
            if replan || watched.isEmpty {
                await plan(monitor, store: store)
            }
            do {
                for try await event in await monitor.events {
                    guard !Task.isCancelled else { return }
                    if event.identifier == homeID {
                        if event.state == .unsatisfied {
                            await plan(monitor, store: store)
                        }
                    } else if event.state == .satisfied {
                        await arrived(at: UnigridsID(event.identifier), store: store)
                    }
                }
            } catch {
                listening = nil
            }
        }

        /// The nearest nineteen places to watch, and a ring around the reader.
        ///
        /// Without a fix the set cannot move, and the ring that asked for it has already
        /// fired, so it would never ask again. It is put back as if the reader were inside,
        /// which has Core Location look again and fire it once more when it sees otherwise.
        private static func plan(_ monitor: CLMonitor, store: any ReferenceStore) async {
            guard let here = await OnSiteCheck().currentCoordinate() else {
                let record = await monitor.record(for: homeID)
                if let ring = record?.condition as? CLMonitor.CircularGeographicCondition {
                    await monitor.add(ring, identifier: homeID, assuming: .satisfied)
                }
                return
            }
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
            await monitor.add(
                CLMonitor.CircularGeographicCondition(
                    center: here.clCoordinate,
                    radius: homeRadius
                ),
                identifier: homeID,
                assuming: .satisfied
            )
            let nearest = store.nearest(
                to: here, limit: 40, tiers: [.nationalPark, .npsUnit, .statePark]
            )
            .filter { store.boundary(for: $0.id) != nil }
            .prefix(19)
            for place in nearest {
                let box = store.frame(for: place)
                let corner = Coordinate(latitude: box.north, longitude: box.east)
                let radius = min(max(place.centre.distance(to: corner), 400), 50000)
                await monitor.add(
                    CLMonitor.CircularGeographicCondition(
                        center: place.centre.clCoordinate,
                        radius: radius
                    ),
                    identifier: place.id.rawValue,
                    assuming: here.distance(to: place.centre) < radius ? .satisfied : .unsatisfied
                )
            }
        }

        /// Inside the circle is not inside the park: check the outline before suggesting.
        private static func arrived(at placeID: UnigridsID, store: any ReferenceStore) async {
            guard let place = store.place(placeID) else { return }
            let inside = await OnSiteCheck().isOnSite(
                at: place,
                boundary: store.boundary(for: placeID)
            )
            let now = Date()
            guard inside,
                  AppServices.detected.add(
                      placeID,
                      at: now,
                      calendar: UnigridsCalendar.gregorian(at: place)
                  )
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "Looks like you're in \(place.name)"
            content.body = "Log a visit? Nothing is logged until you say so."
            content.sound = .default
            content.userInfo = [
                NotificationRoute.key: NotificationRoute.arrival.rawValue,
                "place": placeID.rawValue,
                "date": now.timeIntervalSince1970,
            ]
            let request = UNNotificationRequest(
                identifier: "arrival-\(placeID.rawValue)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// Asks for Always location permission, which iOS grants in two steps: while in use
    /// first, then always.
    @MainActor
    final class LocationPermission: NSObject, CLLocationManagerDelegate {
        private let manager = CLLocationManager()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var askedForAlways = false
        private static var current: LocationPermission?

        static func requestAlways() async -> Bool {
            let permission = LocationPermission()
            current = permission
            defer { current = nil }
            return await permission.request()
        }

        private func request() async -> Bool {
            manager.delegate = self
            switch manager.authorizationStatus {
            case .authorizedAlways:
                return true
            case .denied, .restricted:
                return false
            default:
                return await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    if manager.authorizationStatus == .notDetermined {
                        manager.requestWhenInUseAuthorization()
                    } else {
                        askedForAlways = true
                        watchForReturn()
                        manager.requestAlwaysAuthorization()
                    }
                }
            }
        }

        nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            let status = manager.authorizationStatus
            Task { @MainActor in self.advance(status) }
        }

        private func advance(_ status: CLAuthorizationStatus) {
            switch status {
            case .authorizedWhenInUse:
                // The upgrade to Always is a second prompt, and declining it ("Keep Only
                // While Using") changes nothing, so no callback comes. The prompt takes the
                // app out of the foreground; its answer is read when the app comes back,
                // however long the reader took.
                guard !askedForAlways else { return }
                askedForAlways = true
                watchForReturn()
                manager.requestAlwaysAuthorization()
            case .authorizedAlways:
                finish(true)
            case .denied, .restricted:
                finish(false)
            default:
                break
            }
        }

        private func watchForReturn() {
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: UIApplication.didBecomeActiveNotification
                ) {
                    guard let self else { return }
                    finish(manager.authorizationStatus == .authorizedAlways)
                    return
                }
            }
        }

        private func finish(_ granted: Bool) {
            continuation?.resume(returning: granted)
            continuation = nil
        }
    }
#endif

// MARK: - Views

/// The arrivals waiting for an answer, at the top of Trips.
struct DetectedVisitsSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(DetectedVisits.self) private var detected: DetectedVisits?
    let visits: [Visit]
    /// Hosted by the screen rather than this section, which disappears as soon as the
    /// arrival is logged and would take its sheet with it.
    let onLog: (DetectedVisits.Suggestion) -> Void

    private var suggestions: [DetectedVisits.Suggestion] {
        DetectedVisits.unanswered(detected?.pending ?? [], visits: visits, store: store)
    }

    var body: some View {
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { suggestion in
                    let place = store.place(UnigridsID(suggestion.placeID))
                    HStack(spacing: 12) {
                        if let place {
                            SitePin(place: place)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place?.name ?? suggestion.placeID)
                                .font(UnigridStyle.rowTitle)
                                .foregroundStyle(style.ink)
                            Text(
                                "Arrived "
                                    + suggestion.date.formatted(.relative(presentation: .named))
                            )
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                        }
                        Spacer(minLength: 8)
                        Button("Check in") { onLog(suggestion) }
                            .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                        Button {
                            detected?.dismiss(suggestion)
                        } label: {
                            Image(.dismiss)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Not now")
                    }
                    .listRowBackground(Color.clear)
                }
                ListNotes {
                    Text("Noticed on this device. Nothing is logged until you say so.")
                        .font(UnigridStyle.caption)
                }
            } header: {
                SectionHead("Did you arrive?", detail: "\(suggestions.count)")
            }
        }
    }
}

/// The Settings switch for detection.
struct VisitDetectionToggle: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @AppStorage(DetectedVisits.enabledKey) private var enabled = false
    @State private var notice: String?

    var body: some View {
        #if os(iOS)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Suggest a visit when I arrive", isOn: Binding(
                    get: { enabled },
                    set: { isOn in
                        Task {
                            if isOn {
                                let granted = await VisitDetection.enable(store: store)
                                notice = granted ? nil
                                    : "Needs location access set to Always in Settings › Privacy."
                            } else {
                                await VisitDetection.disable()
                            }
                        }
                    }
                ))
                if let notice {
                    Text(notice)
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.seal)
                }
            }
        #else
            Text("Arrival suggestions are on iPhone and iPad, where the device travels with you.")
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
        #endif
    }
}
