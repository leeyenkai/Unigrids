import Foundation

/// One polygon of a place's outline: an exterior ring and any holes cut out of it.
///
/// Rings are closed implicitly — the last point joins the first — and their winding is not
/// relied on, because the sources do not agree on one.
public struct BoundaryPolygon: Hashable, Sendable {
    public let exterior: [Coordinate]
    public let holes: [[Coordinate]]

    public init(exterior: [Coordinate], holes: [[Coordinate]] = []) {
        self.exterior = exterior
        self.holes = holes
    }

    /// Every ring, exterior first.
    public var rings: [[Coordinate]] {
        [exterior] + holes
    }

    /// Whether a point lies inside the polygon and outside its holes.
    ///
    /// Even–odd ray casting over every ring at once: a point inside a hole crosses the
    /// exterior and the hole, an even count, and so reads as outside without the holes
    /// needing separate treatment. Planar in degrees, which is exact enough at the scale a
    /// park outline is tapped at and wrong only for a ring that crosses the antimeridian —
    /// none of the bundled ones do, and `BundledDataTests` holds that.
    public func contains(_ point: Coordinate) -> Bool {
        var inside = false
        for ring in rings where ring.count >= 3 {
            var previous = ring[ring.count - 1]
            for current in ring {
                let crosses = (current.latitude > point.latitude)
                    != (previous.latitude > point.latitude)
                if crosses {
                    let slope = (previous.longitude - current.longitude)
                        / (previous.latitude - current.latitude)
                    let crossingLongitude = current.longitude
                        + (point.latitude - current.latitude) * slope
                    if point.longitude < crossingLongitude {
                        inside.toggle()
                    }
                }
                previous = current
            }
        }
        return inside
    }
}

/// A place's outline: one or more polygons and the box around them
/// (SPECIFICATION.md §5: "park boundaries appear as tinted polygons").
///
/// Reference data. The pipeline generalises each outline from the NPS boundary service or
/// PAD-US and ships it as encoded polylines (`Polyline`), which is what this decodes.
public struct PlaceBoundary: Hashable, Sendable {
    public let polygons: [BoundaryPolygon]
    public let extent: BoundingBox

    public init(polygons: [BoundaryPolygon], extent: BoundingBox? = nil) {
        self.polygons = polygons
        self.extent = extent ?? BoundingBox.enclosing(polygons.flatMap(\.exterior))
            ?? BoundingBox(south: 0, west: 0, north: 0, east: 0)
    }

    /// Whether a point falls inside the outline. The extent is checked first because it is
    /// cheap, and most points on a national map are nowhere near a given park.
    public func contains(_ point: Coordinate) -> Bool {
        guard extent.contains(point) else { return false }
        return polygons.contains { $0.contains(point) }
    }

    /// How many vertices the outline carries, for budgeting what the map draws.
    public var pointCount: Int {
        polygons.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
    }
}

extension PlaceBoundary: Codable {
    private enum CodingKeys: String, CodingKey {
        case bbox
        case polygons
    }

    /// `{"bbox": [south, west, north, east], "polygons": [["exterior", "hole", …], …]}`,
    /// each ring an encoded polyline.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encoded = try container.decode([[String]].self, forKey: .polygons)
        let polygons = encoded.compactMap { rings -> BoundaryPolygon? in
            guard let first = rings.first else { return nil }
            return BoundaryPolygon(
                exterior: Polyline.decode(first),
                holes: rings.dropFirst().map(Polyline.decode)
            )
        }
        let box = try container.decodeIfPresent([Double].self, forKey: .bbox)
        let extent = box.flatMap { values -> BoundingBox? in
            guard values.count == 4 else { return nil }
            return BoundingBox(south: values[0], west: values[1], north: values[2], east: values[3])
        }
        self.init(polygons: polygons, extent: extent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            [extent.south, extent.west, extent.north, extent.east],
            forKey: .bbox
        )
        try container.encode(
            polygons.map { $0.rings.map(Polyline.encode) },
            forKey: .polygons
        )
    }
}

extension BoundingBox {
    /// The smallest box around some coordinates, or `nil` for none.
    public static func enclosing(_ coordinates: [Coordinate]) -> BoundingBox? {
        guard let first = coordinates.first else { return nil }
        var box = (
            south: first.latitude, west: first.longitude,
            north: first.latitude, east: first.longitude
        )
        for coordinate in coordinates.dropFirst() {
            box.south = min(box.south, coordinate.latitude)
            box.north = max(box.north, coordinate.latitude)
            box.west = min(box.west, coordinate.longitude)
            box.east = max(box.east, coordinate.longitude)
        }
        return BoundingBox(south: box.south, west: box.west, north: box.north, east: box.east)
    }

    /// The box's area in square degrees. Only ever compared with another box's, to decide
    /// which of two overlapping places a tap meant: the smaller one.
    public var degreeArea: Double {
        (north - south) * (east - west)
    }

    /// Whether two boxes overlap at all.
    public func intersects(_ other: BoundingBox) -> Bool {
        south <= other.north && north >= other.south && west <= other.east && east >= other.west
    }

    /// The smallest box holding both.
    public func union(_ other: BoundingBox) -> BoundingBox {
        BoundingBox(
            south: min(south, other.south),
            west: min(west, other.west),
            north: max(north, other.north),
            east: max(east, other.east)
        )
    }
}
