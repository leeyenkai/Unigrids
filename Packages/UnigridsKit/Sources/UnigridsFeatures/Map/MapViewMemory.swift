import Foundation
import MapKit
import UnigridsCore

/// Where the map was left, so it reopens there (SPECIFICATION.md §5).
///
/// Kept in UserDefaults directly, not `@AppStorage`: a pan must not redraw the map screen.
enum MapViewMemory {
    /// `south,west,north,east`.
    static let key = "map.lastView"

    static func save(_ region: MKCoordinateRegion) {
        let view = MapRegions.encode(BoundingBox(
            south: region.center.latitude - region.span.latitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2,
            north: region.center.latitude + region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2
        ))
        UserDefaults.standard.set(view, forKey: key)
    }

    /// Where the map opens: where it was left, else the reader's own country if its
    /// places ship (read from the device's region, on the device), else the Lower 48.
    static func openingBox(among countries: [Country]) -> BoundingBox {
        if let box = UserDefaults.standard.string(forKey: key).flatMap(MapRegions.decode) {
            return box
        }
        let home = MapRegions.homeCountry(
            regionCode: Locale.current.region?.identifier,
            among: Set(countries)
        )
        return MapRegions.home(home)
    }
}
