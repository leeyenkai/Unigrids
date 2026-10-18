import Foundation

/// A WGS 84 position.
///
/// `UnigridsCore` stays free of CoreLocation and MapKit so the domain rules test in
/// milliseconds; feature code converts to `CLLocationCoordinate2D` at the boundary.
public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in metres, by the haversine formula.
    ///
    /// Accurate enough for "nearest unvisited park" and for deciding whether a check-in
    /// happened on site. Trail lengths are measured by the pipeline, not here.
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_008.8
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = lat2 - lat1
        let deltaLon = (other.longitude - longitude) * .pi / 180

        let a = (sin(deltaLat / 2) * sin(deltaLat / 2))
            + (cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2))
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A latitude/longitude rectangle, used for park extents and map camera framing.
public struct BoundingBox: Hashable, Sendable, Codable {
    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    public var centre: Coordinate {
        Coordinate(latitude: (south + north) / 2, longitude: (west + east) / 2)
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= south
            && coordinate.latitude <= north
            && coordinate.longitude >= west
            && coordinate.longitude <= east
    }

    /// The box grown by a fraction of its own size, for framing a park with margin.
    public func expanded(by fraction: Double) -> BoundingBox {
        let latitudePadding = (north - south) * fraction
        let longitudePadding = (east - west) * fraction
        return BoundingBox(
            south: south - latitudePadding,
            west: west - longitudePadding,
            north: north + latitudePadding,
            east: east + longitudePadding
        )
    }
}
