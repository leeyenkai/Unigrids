import Foundation

/// Camera framing for the 3D explorer (SPECIFICATION.md §7), as plain numbers so the
/// shots can be tested without MapKit.
///
/// MapKit's 3D camera is a point to look at, a distance back from it, a compass heading
/// and a pitch. These pick them so a park, a sight and a trail each fill the frame and are
/// looked at from a sensible side.
public enum ExplorerCamera {
    /// A shot: where the camera looks, from how far, facing which way, tilted how much.
    public struct Shot: Hashable, Sendable {
        public let centre: Coordinate
        public let distance: Double
        public let heading: Double
        public let pitch: Double

        public init(centre: Coordinate, distance: Double, heading: Double, pitch: Double) {
            self.centre = centre
            self.distance = distance
            self.heading = heading
            self.pitch = pitch
        }
    }

    /// The initial compass bearing from one point to another, in degrees clockwise from
    /// north.
    public static func bearing(from start: Coordinate, to end: Coordinate) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let east = sin(deltaLon) * cos(lat2)
        let north = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(east, north) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// How far back to stand to see a box, in metres: a little over its longer side, so
    /// a pitched view still holds the whole of it. Never closer than `minimum`.
    public static func distance(toFrame box: BoundingBox, minimum: Double = 1500) -> Double {
        let height = (box.north - box.south) * 111_000
        let width = (box.east - box.west) * 111_000 * cos(box.centre.latitude * .pi / 180)
        return max(max(height, width) * 2.2, minimum)
    }

    /// The whole place, from the south and tilted, as the explorer opens. A little closer
    /// than a flat framing would stand: MapKit flattens its camera as it climbs, and a
    /// park seen from too high is a map, not a landscape.
    public static func overview(of box: BoundingBox) -> Shot {
        let framed = distance(toFrame: box, minimum: 4000) * 0.7
        let southOfCentre = Coordinate(
            latitude: box.centre.latitude - (box.north - box.south) * 0.12,
            longitude: box.centre.longitude
        )
        return Shot(centre: southOfCentre, distance: framed, heading: 0, pitch: 55)
    }

    /// A sight, close and steep, looked at from the side of the park it is approached
    /// from: the camera stands between the park's middle and the sight, facing outwards,
    /// so the sight is seen with the park behind the viewer rather than the void beyond.
    public static func sight(_ point: Coordinate, in park: BoundingBox) -> Shot {
        let centre = park.centre
        let heading = point.distance(to: centre) < 200 ? 0 : bearing(from: centre, to: point)
        return Shot(centre: point, distance: 2200, heading: heading, pitch: 66)
    }

    /// A trail: framed whole, looking along it from its start towards its end.
    public static func trail(_ path: [Coordinate]) -> Shot? {
        guard let first = path.first, let last = path.last,
              let box = BoundingBox.enclosing(path) else { return nil }
        let heading = first.distance(to: last) < 100 ? 0 : bearing(from: first, to: last)
        return Shot(
            centre: box.centre,
            distance: distance(toFrame: box, minimum: 1200),
            heading: heading,
            pitch: 58
        )
    }

    /// The headings a fly-through orbits through at a stop: a quarter turn in even steps,
    /// starting from the arrival heading. Slow enough to read the ground.
    public static func orbit(from heading: Double, steps: Int = 3, sweep: Double = 90) -> [Double] {
        guard steps > 0 else { return [] }
        return (1 ... steps).map { step in
            (heading + sweep * Double(step) / Double(steps)).truncatingRemainder(dividingBy: 360)
        }
    }
}
