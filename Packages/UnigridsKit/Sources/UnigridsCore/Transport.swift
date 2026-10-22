import Foundation

/// A named line drawn on the map: an Interstate, a US route, an Amtrak service, a scenic
/// byway. One or more paths, because a route the sources publish in pieces stays in
/// pieces rather than being joined across a gap that is really there.
///
/// Reference data, shipped as encoded polylines like the outlines (`Polyline`).
public struct RouteLine: Hashable, Sendable, Identifiable {
    /// "I-80", "US 50", "California Zephyr", or a place's id for a byway.
    public let name: String
    public let paths: [[Coordinate]]
    public let extent: BoundingBox

    public var id: String {
        name
    }

    public init(name: String, paths: [[Coordinate]], extent: BoundingBox? = nil) {
        self.name = name
        self.paths = paths
        self.extent = extent ?? BoundingBox.enclosing(paths.flatMap(\.self))
            ?? BoundingBox(south: 0, west: 0, north: 0, east: 0)
    }

    /// The point halfway along the longest path, for a byway's pin.
    public var midpoint: Coordinate? {
        guard let path = paths.max(by: { RouteGeometry.length($0) < RouteGeometry.length($1) })
        else { return nil }
        return RouteGeometry.point(along: path, fraction: 0.5)
    }

    /// Total length in metres.
    public var length: Double {
        paths.reduce(0) { $0 + RouteGeometry.length($1) }
    }

    /// How far a point is from the nearest part of the line, in metres.
    public func distance(to point: Coordinate) -> Double {
        paths.map { RouteGeometry.distance(from: point, to: $0) }.min() ?? .infinity
    }
}

extension RouteLine: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case paths
        case bbox
    }

    /// `{"name": "I-80", "bbox": [south, west, north, east], "paths": ["encoded", …]}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        let paths = try container.decode([String].self, forKey: .paths).map(Polyline.decode)
        let box = try container.decodeIfPresent([Double].self, forKey: .bbox)
        let extent = box.flatMap { values -> BoundingBox? in
            guard values.count == 4 else { return nil }
            return BoundingBox(south: values[0], west: values[1], north: values[2], east: values[3])
        }
        self.init(name: name, paths: paths.filter { $0.count >= 2 }, extent: extent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(
            [extent.south, extent.west, extent.north, extent.east], forKey: .bbox
        )
        try container.encode(paths.map(Polyline.encode), forKey: .paths)
    }
}

/// An Amtrak station the map can mark.
public struct RailStation: Identifiable, Hashable, Sendable, Codable {
    /// Amtrak's three-letter station code, the stable key.
    public let code: String
    public let name: String
    public let city: String?
    public let state: USState?
    public let location: Coordinate

    public var id: String {
        code
    }

    public init(
        code: String,
        name: String,
        city: String? = nil,
        state: USState? = nil,
        location: Coordinate
    ) {
        self.code = code
        self.name = name
        self.city = city
        self.state = state
        self.location = location
    }
}

/// The roads and railways the map can lay over the public lands (SPECIFICATION.md §5).
///
/// From the National Transportation Atlas Database: the Interstates and the US routes on
/// the National Highway System, and the Amtrak network with its train stations.
public struct TransportNetwork: Hashable, Sendable, Codable {
    public let interstates: [RouteLine]
    public let usHighways: [RouteLine]
    public let amtrakRoutes: [RouteLine]
    public let amtrakStations: [RailStation]

    public init(
        interstates: [RouteLine] = [],
        usHighways: [RouteLine] = [],
        amtrakRoutes: [RouteLine] = [],
        amtrakStations: [RailStation] = []
    ) {
        self.interstates = interstates
        self.usHighways = usHighways
        self.amtrakRoutes = amtrakRoutes
        self.amtrakStations = amtrakStations
    }

    public static let empty = TransportNetwork()

    /// A cheap fingerprint, for telling a loaded network from the empty one without
    /// comparing every coordinate.
    public var signature: Int {
        var hasher = Hasher()
        hasher.combine(interstates.count)
        hasher.combine(usHighways.count)
        hasher.combine(amtrakRoutes.count)
        hasher.combine(amtrakStations.count)
        return hasher.finalize()
    }

    public var isEmpty: Bool {
        interstates.isEmpty && usHighways.isEmpty && amtrakRoutes.isEmpty
            && amtrakStations.isEmpty
    }

    public func lines(for layer: TransportLayer) -> [RouteLine] {
        switch layer {
        case .interstates: interstates
        case .usHighways: usHighways
        case .amtrak: amtrakRoutes
        }
    }

    /// The Amtrak services that call within a distance of a point, by name — "the
    /// Empire Builder stops near Glacier" — for a place's getting-there note.
    public func amtrakRoutes(near point: Coordinate, within metres: Double) -> [RouteLine] {
        // A degree of latitude is never less than 110 km, so this pad is never too small
        // to keep a route the distance test would pass. It only spares that test.
        let pad = metres / 110_000 * 2
        return amtrakRoutes
            .filter { route in
                let box = route.extent
                return point.latitude >= box.south - pad && point.latitude <= box.north + pad
                    && point.longitude >= box.west - pad * 3
                    && point.longitude <= box.east + pad * 3
                    && route.distance(to: point) <= metres
            }
            .sorted { $0.name < $1.name }
    }

    /// The nearest train station to a point, with its distance in metres.
    public func nearestStation(to point: Coordinate) -> (station: RailStation, metres: Double)? {
        amtrakStations
            .map { ($0, $0.location.distance(to: point)) }
            .min { $0.1 < $1.1 }
            .map { (station: $0.0, metres: $0.1) }
    }
}

/// The transport layers a reader can switch on over the map.
public enum TransportLayer: String, CaseIterable, Sendable, Codable, Identifiable {
    case interstates
    case usHighways
    case amtrak

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .interstates: "Interstates"
        case .usHighways: "US highways"
        case .amtrak: "Amtrak"
        }
    }

    public var detail: String {
        switch self {
        case .interstates: "The Interstate Highway System"
        case .usHighways: "US routes on the National Highway System"
        case .amtrak: "Every Amtrak route, with its train stations close up"
        }
    }

    /// Below this latitude span the layer is worth drawing. US routes are a dense mesh at
    /// country scale, so they wait for regional zoom; the others show at every zoom.
    public var maximumSpan: Double {
        switch self {
        case .interstates, .amtrak: .infinity
        case .usHighways: 24
        }
    }
}

/// Flat-earth geometry along lines, good to a fraction of a percent over the distances a
/// tap or a byway spans.
public enum RouteGeometry {
    /// A path's length in metres.
    public static func length(_ path: [Coordinate]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point a fraction of the way along a path.
    public static func point(along path: [Coordinate], fraction: Double) -> Coordinate? {
        guard let first = path.first else { return nil }
        let target = length(path) * min(max(fraction, 0), 1)
        var walked = 0.0
        for (start, end) in zip(path, path.dropFirst()) {
            let leg = start.distance(to: end)
            if walked + leg >= target, leg > 0 {
                let share = (target - walked) / leg
                return Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * share,
                    longitude: start.longitude + (end.longitude - start.longitude) * share
                )
            }
            walked += leg
        }
        return path.last ?? first
    }

    /// The shortest distance from a point to a path, in metres.
    ///
    /// Each segment is projected onto a plane tangent at the point — longitude scaled by
    /// the cosine of latitude — which is what makes "within 12 points of the line" mean
    /// the same thing across the country.
    public static func distance(from point: Coordinate, to path: [Coordinate]) -> Double {
        guard let first = path.first else { return .infinity }
        guard path.count > 1 else { return point.distance(to: first) }
        let metresPerDegree = 111_320.0
        let scale = cos(point.latitude * .pi / 180)
        func project(_ coordinate: Coordinate) -> (x: Double, y: Double) {
            (
                (coordinate.longitude - point.longitude) * scale * metresPerDegree,
                (coordinate.latitude - point.latitude) * metresPerDegree
            )
        }
        var best = Double.infinity
        var previous = project(first)
        for coordinate in path.dropFirst() {
            let current = project(coordinate)
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            let lengthSquared = dx * dx + dy * dy
            let along = lengthSquared == 0 ? 0
                : max(0, min(1, -(previous.x * dx + previous.y * dy) / lengthSquared))
            let nearestX = previous.x + along * dx
            let nearestY = previous.y + along * dy
            best = min(best, (nearestX * nearestX + nearestY * nearestY).squareRoot())
            previous = current
        }
        return best
    }
}

/// How to reach a place by train: the nearest Amtrak station and the services that call
/// there (SPECIFICATION.md §10, getting there).
public struct TrainAccess: Hashable, Sendable {
    public let station: RailStation
    /// Straight-line metres from the station to the place's outline — zero when the
    /// station is inside it — or to its centre when it has no outline.
    public let metres: Double
    /// Whether `metres` is to the outline rather than the centre.
    public let measuredToBoundary: Bool
    /// The Amtrak services calling at the station, by name.
    public let services: [String]
}

extension TransportNetwork {
    /// The nearest station within `limit` metres of a place, or `nil` if there is none.
    ///
    /// Distances are straight lines, and the screens say so: this answers "is there a
    /// train anywhere near", not "how long is the taxi".
    public func trainAccess(
        to place: Place,
        boundary: PlaceBoundary?,
        within limit: Double = 100_000
    ) -> TrainAccess? {
        let reach = limit + (boundary.map { radius(of: $0.extent) } ?? 0)
        let candidates = amtrakStations.filter { $0.location.distance(to: place.centre) <= reach }
        let measured = candidates.map { station -> (RailStation, Double) in
            guard let boundary
            else { return (station, station.location.distance(to: place.centre)) }
            if boundary.contains(station.location) {
                return (station, 0)
            }
            let edge = boundary.polygons
                .map { polygon in
                    let ring = polygon.exterior + polygon.exterior.prefix(1)
                    return RouteGeometry.distance(from: station.location, to: ring)
                }
                .min() ?? .infinity
            return (station, edge)
        }
        guard let (station, metres) = measured.min(by: { $0.1 < $1.1 }), metres <= limit
        else { return nil }
        let services = amtrakRoutes(near: station.location, within: 1500).map(\.name)
        return TrainAccess(
            station: station,
            metres: metres,
            measuredToBoundary: boundary != nil,
            services: services
        )
    }

    private func radius(of box: BoundingBox) -> Double {
        Coordinate(latitude: box.south, longitude: box.west)
            .distance(to: Coordinate(latitude: box.north, longitude: box.east)) / 2
    }
}
