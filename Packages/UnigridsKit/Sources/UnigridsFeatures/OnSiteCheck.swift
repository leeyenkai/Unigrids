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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Whether the reader is inside the place's outline — or, for a place without one,
    /// within three kilometres of its centre. `false` when location is unavailable or
    /// declined; the stamp is simply unverified, never refused.
    func isOnSite(at place: Place, boundary: PlaceBoundary?) async -> Bool {
        guard let location = await currentLocation() else { return false }
        let here = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        if let boundary {
            return boundary.contains(here)
        }
        return here.distance(to: place.centre) < 3000
    }

    /// Where the reader is, once, for "nearest unvisited park". Not stored.
    func currentCoordinate() async -> Coordinate? {
        guard let location = await currentLocation() else { return nil }
        return Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }

    private func currentLocation() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return nil
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
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
