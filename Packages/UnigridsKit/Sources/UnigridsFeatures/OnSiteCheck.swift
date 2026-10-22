import CoreLocation
import UnigridsCore
import UnigridsReference

/// One question, asked once: is the reader at this place right now?
///
/// It answers the passport's verified tick (SPECIFICATION.md §9). The location is read,
/// compared with the place's outline, and dropped — never stored, never uploaded, never
/// kept as a track (§15). When-in-use permission only, and asked for only at the moment a
/// reader stamps.
@MainActor
final class OnSiteCheck: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizing: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether the reader is inside the place's outline — or, for a place without one,
    /// within three kilometres of its centre. `false` when location is unavailable or
    /// declined; the stamp is simply unverified, never refused.
    func isOnSite(
        at place: Place,
        boundary: PlaceBoundary?,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        guard let location = await currentLocation(timeout: timeout) else { return false }
        let here = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        if let boundary {
            return boundary.contains(here)
        }
        return here.distance(to: place.centre) < 3000
    }

    /// Where the reader is, once, for the map and "nearest unvisited park". Not stored.
    func currentCoordinate(timeout: Duration = .seconds(15)) async -> Coordinate? {
        guard let location = await currentLocation(timeout: timeout) else { return nil }
        return Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    /// Whether the reader has said no to location, so a screen can say why it has none.
    static var isRefused: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    /// One fix, or nil. A first request asks for permission and waits for the answer
    /// before asking for a position — asked straight away, the position request fails
    /// while the prompt is still up. Gives up after `timeout`.
    private func currentLocation(timeout: Duration) async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { continuation in
                authorizing = continuation
                manager.requestWhenInUseAuthorization()
            }
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return nil
        }
        let deadline = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        defer { deadline.cancel() }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(
        _: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let latest = locations.last
        Task { @MainActor in self.finish(latest) }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: any Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            self.authorizing?.resume()
            self.authorizing = nil
            if status == .denied || status == .restricted {
                self.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}
