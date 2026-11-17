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
        let own = Shortcut(name: homeName(country), box: home(country))
        let more: [Shortcut] = switch country {
        case .unitedStates: unitedStatesShortcuts
        case .japan: japanShortcuts
        case .norway: norwayShortcuts
        case .newZealand: newZealandShortcuts
        case .australia: australiaShortcuts
        case .canada: canadaShortcuts
        }
        return [own] + more
    }

    /// The name of a country's home view on its chip.
    private static func homeName(_ country: Country) -> String {
        switch country {
        case .unitedStates: "Lower 48"
        case .japan: "Japan"
        case .norway: "Norway"
        case .newZealand: "New Zealand"
        case .australia: "Australia"
        case .canada: "Canada"
        }
    }

    private static let unitedStatesShortcuts: [Shortcut] = [
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

    private static let japanShortcuts: [Shortcut] = [
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

    private static let norwayShortcuts: [Shortcut] = [
        Shortcut(
            name: "Svalbard",
            box: BoundingBox(south: 76.4, west: 10.4, north: 80.9, east: 33.6)
        ),
    ]

    private static let newZealandShortcuts: [Shortcut] = [
        Shortcut(
            name: "North Island",
            box: BoundingBox(south: -41.7, west: 172.5, north: -34.3, east: 178.6)
        ),
        Shortcut(
            name: "South Island",
            box: BoundingBox(south: -47.4, west: 166.3, north: -40.4, east: 174.5)
        ),
        // East of 180°: the islands keep their own box rather than one that wraps.
        Shortcut(
            name: "Chatham Islands",
            box: BoundingBox(south: -44.4, west: -177.0, north: -43.6, east: -176.1)
        ),
    ]

    private static let australiaShortcuts: [Shortcut] = [
        Shortcut(
            name: "Tasmania",
            box: BoundingBox(south: -43.7, west: 143.8, north: -39.5, east: 148.6)
        ),
        Shortcut(
            name: "Top End",
            box: BoundingBox(south: -15.5, west: 129.0, north: -11.0, east: 137.0)
        ),
        Shortcut(
            name: "Christmas Island",
            box: BoundingBox(south: -10.6, west: 105.5, north: -10.4, east: 105.8)
        ),
        Shortcut(
            name: "Norfolk Island",
            box: BoundingBox(south: -29.2, west: 167.9, north: -28.9, east: 168.1)
        ),
        Shortcut(
            name: "Cocos (Keeling)",
            box: BoundingBox(south: -12.25, west: 96.8, north: -11.8, east: 96.95)
        ),
    ]

    private static let canadaShortcuts: [Shortcut] = [
        Shortcut(
            name: "The Rockies",
            box: BoundingBox(south: 48.9, west: -122.0, north: 53.5, east: -113.0)
        ),
        Shortcut(
            name: "Southern Ontario",
            box: BoundingBox(south: 41.6, west: -83.2, north: 46.0, east: -74.3)
        ),
        Shortcut(
            name: "Atlantic",
            box: BoundingBox(south: 43.4, west: -67.5, north: 52.0, east: -52.6)
        ),
        Shortcut(
            name: "The North",
            box: BoundingBox(south: 60.0, west: -141.0, north: 83.2, east: -61.0)
        ),
    ]

    /// Where the map opens for a reader in this country: the Lower 48, Japan's main
    /// islands, mainland Norway.
    public static func home(_ country: Country) -> BoundingBox {
        switch country {
        case .unitedStates: BoundingBox(south: 24.5, west: -125, north: 49.5, east: -66.5)
        case .japan: BoundingBox(south: 30.0, west: 128.0, north: 45.6, east: 146.0)
        case .norway: BoundingBox(south: 57.9, west: 4.5, north: 71.2, east: 31.2)
        case .newZealand: BoundingBox(south: -47.4, west: 166.3, north: -34.3, east: 178.6)
        case .australia: BoundingBox(south: -43.8, west: 112.9, north: -10.5, east: 153.7)
        case .canada: BoundingBox(south: 41.6, west: -141.0, north: 70.0, east: -52.6)
        }
    }

    /// The country among `present` whose map holds `point` — its home view or any of its
    /// shortcuts — or nil over open sea. Where two countries' views overlap (the Lower 48
    /// reaches into southern Ontario), the smallest view holding the point wins.
    public static func country(at point: Coordinate, among present: [Country]) -> Country? {
        var best: (country: Country, area: Double)?
        for country in present {
            for shortcut in shortcuts(in: country) {
                guard shortcut.box.expanded(by: 0.1).contains(point) else { continue }
                let area = (shortcut.box.north - shortcut.box.south)
                    * (shortcut.box.east - shortcut.box.west)
                if best.map({ area < $0.area }) ?? true {
                    best = (country, area)
                }
            }
        }
        return best?.country
    }

    /// Every country at once, for a reader with places in more than one: from Rakiura to
    /// Canada's Arctic islands.
    public static let world = BoundingBox(south: -50, west: -179.5, north: 83.5, east: 179.5)

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
