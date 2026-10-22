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
    func add(_ placeID: UnigridsID, at date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        guard !pending.contains(where: {
            $0.placeID == placeID.rawValue && Calendar.current.isDate($0.date, inSameDayAs: day)
        }) else { return false }
        pending.append(Suggestion(placeID: placeID.rawValue, date: date))
        // A week-old suggestion is a visit the reader chose not to log.
        pending.removeAll { Date().timeIntervalSince($0.date) > 7 * 86400 }
        save()
        return true
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
            let monitor = await CLMonitor(monitorName)
            for identifier in await monitor.identifiers {
                await monitor.remove(identifier)
            }
        }

        private static func listen(store: any ReferenceStore, replan: Bool = false) async {
            let monitor = await CLMonitor(monitorName)
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
        private static func plan(_ monitor: CLMonitor, store: any ReferenceStore) async {
            guard let here = await OnSiteCheck().currentCoordinate() else { return }
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
            guard inside, AppServices.detected.add(placeID, at: Date()) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Looks like you're in \(place.name)"
            content.body = "Log a visit? Nothing is logged until you say so."
            content.sound = .default
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
                manager.requestAlwaysAuthorization()
                // If the reader declines the upgrade, no further callback comes; settle
                // for what there is after a moment.
                Task {
                    try? await Task.sleep(for: .seconds(8))
                    finish(manager.authorizationStatus == .authorizedAlways)
                }
            case .authorizedAlways:
                finish(true)
            case .denied, .restricted:
                finish(false)
            default:
                break
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
    @State private var logging: DetectedVisits.Suggestion?

    private var suggestions: [DetectedVisits.Suggestion] {
        (detected?.pending ?? []).filter { suggestion in
            !visits.contains {
                $0.placeID == suggestion.placeID
                    && Calendar.current.isDate($0.date, inSameDayAs: suggestion.date)
            }
        }
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
                        Button("Log") { logging = suggestion }
                            .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                        Button {
                            detected?.dismiss(suggestion)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Not now")
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                SectionHead("Did you arrive?", detail: "\(suggestions.count)")
            } footer: {
                Text("Noticed on this device. Nothing is logged until you say so.")
                    .font(UnigridStyle.caption)
            }
            .sheet(item: $logging) { suggestion in
                if let place = store.place(UnigridsID(suggestion.placeID)) {
                    CheckInSheet(place: place, date: suggestion.date, source: .autoDetected)
                }
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
