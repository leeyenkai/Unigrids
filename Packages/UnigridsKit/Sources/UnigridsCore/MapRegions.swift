import Foundation

/// The map's region shortcuts and home views, country by country (SPECIFICATION.md §5:
/// Alaska, Hawaii and the territories one tap away; ADR 0013 for the countries after).
public enum MapRegions {
    public struct Shortcut: Hashable, Sendable {
        public let name: String
        public let box: BoundingBox
    }

    /// A country's shortcuts, its home view first.
    public static func shortcuts(in country: Country) -> [Shortcut] {
        switch country {
        case .unitedStates:
            [
                Shortcut(name: "Lower 48", box: home(country)),
                Shortcut(
                    name: "Alaska",
                    box: BoundingBox(south: 54.5, west: -168, north: 71.5, east: -137)
                ),
                Shortcut(
                    name: "Hawaiʻi",
                    box: BoundingBox(south: 18.8, west: -160.4, north: 22.3, east: -154.7)
                ),
                Shortcut(
                    name: "Caribbean",
                    box: BoundingBox(south: 17.6, west: -67.4, north: 18.6, east: -64.5)
                ),
                // Guam and Saipan: War in the Pacific and American Memorial Park.
                Shortcut(
                    name: "Guam & N. Marianas",
                    box: BoundingBox(south: 13.2, west: 144.5, north: 15.4, east: 146.0)
                ),
                Shortcut(
                    name: "American Samoa",
                    box: BoundingBox(south: -14.4, west: -170.9, north: -14.1, east: -169.4)
                ),
            ]
        case .japan:
            [
                Shortcut(name: "Japan", box: home(country)),
                Shortcut(
                    name: "Hokkaido",
                    box: BoundingBox(south: 41.3, west: 139.3, north: 45.6, east: 146.0)
                ),
                Shortcut(
                    name: "Okinawa & Amami",
                    box: BoundingBox(south: 24.0, west: 122.9, north: 28.6, east: 131.4)
                ),
                Shortcut(
                    name: "Ogasawara",
                    box: BoundingBox(south: 24.2, west: 140.8, north: 27.8, east: 142.4)
                ),
            ]
        case .norway:
            [
                Shortcut(name: "Norway", box: home(country)),
                Shortcut(
                    name: "Svalbard",
                    box: BoundingBox(south: 76.4, west: 10.4, north: 80.9, east: 33.6)
                ),
            ]
        }
    }

    /// Where the map opens for a reader in this country: the Lower 48, Japan's main
    /// islands, mainland Norway.
    public static func home(_ country: Country) -> BoundingBox {
        switch country {
        case .unitedStates: BoundingBox(south: 24.5, west: -125, north: 49.5, east: -66.5)
        case .japan: BoundingBox(south: 30.0, west: 128.0, north: 45.6, east: 146.0)
        case .norway: BoundingBox(south: 57.9, west: 4.5, north: 71.2, east: 31.2)
        }
    }

    /// The country among `present` whose map holds `point` — its home view or any of its
    /// shortcuts — or nil over open sea.
    public static func country(at point: Coordinate, among present: [Country]) -> Country? {
        present.first { country in
            shortcuts(in: country).contains { $0.box.expanded(by: 0.1).contains(point) }
        }
    }

    /// Every country at once, for a reader with places in more than one.
    public static let world = BoundingBox(south: -30, west: -175, north: 78, east: 175)

    /// The country whose map a reader in `regionCode` (the device's region, never sent
    /// anywhere) would want first, among those with places: their own, else the US.
    public static func homeCountry(regionCode: String?, among present: Set<Country>) -> Country {
        let own = regionCode.flatMap { Country(rawValue: $0.uppercased()) }
        if let own, present.contains(own) {
            return own
        }
        return .unitedStates
    }

    /// A saved view, written `south,west,north,east`.
    public static func encode(_ box: BoundingBox) -> String {
        [box.south, box.west, box.north, box.east]
            .map { String(format: "%.4f", $0) }
            .joined(separator: ",")
    }

    public static func decode(_ text: String) -> BoundingBox? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts[0] < parts[2], (-90 ... 90).contains(parts[0]),
              (-90 ... 90).contains(parts[2])
        else { return nil }
        return BoundingBox(south: parts[0], west: parts[1], north: parts[2], east: parts[3])
    }
}
