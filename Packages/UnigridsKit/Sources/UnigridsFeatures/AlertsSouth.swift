import Foundation
import UnigridsCore

// Live warnings for New Zealand's parks (SPECIFICATION.md §10, ADR 0014): GeoNet's
// volcanic alert levels, set by GNS Science, for the volcanoes inside a park. No key; the
// request is one fixed URL and says nothing about the reader. Data CC BY 3.0 NZ, © Earth
// Sciences New Zealand, credited in Attributions.

/// GeoNet's current volcanic alert level for each of New Zealand's monitored volcanoes.
///
/// Every volcano carries a level from 0 (no unrest) to 5 (major eruption). A park shows a
/// volcano's level from 1 up; 0 is said in the panel's own words, not as an alert.
enum GeoNetVolcanoes {
    struct Volcano: Hashable, Sendable {
        let id: String
        let name: String
        let location: Coordinate
        let level: Int
        let activity: String
        let hazards: String
    }

    static let url = URL(string: "https://api.geonet.org.nz/volcano/val")
    static let pageURL = "https://www.geonet.org.nz/about/volcano/val"

    static func fetch() async throws -> [Volcano] {
        guard let url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(AbroadFetch.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.geo+json;version=2", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try volcanoes(from: data)
    }

    static func volcanoes(from data: Data) throws -> [Volcano] {
        struct Properties: Decodable {
            let volcanoID: String
            let volcanoTitle: String
            let level: Int
            let activity: String?
            let hazards: String?
        }
        struct Geometry: Decodable {
            let coordinates: [Double]
        }
        struct Feature: Decodable {
            let geometry: Geometry
            let properties: Properties
        }
        struct Collection: Decodable {
            let features: [Lossy<Feature>]
        }
        let features = try lossyValues(JSONDecoder().decode(Collection.self, from: data).features)
        return features.compactMap { feature in
            let point = feature.geometry.coordinates
            guard point.count >= 2 else { return nil }
            return Volcano(
                id: feature.properties.volcanoID,
                name: feature.properties.volcanoTitle,
                location: Coordinate(latitude: point[1], longitude: point[0]),
                level: feature.properties.level,
                activity: feature.properties.activity ?? "",
                hazards: feature.properties.hazards ?? ""
            )
        }
    }

    /// A volcano's level as an alert, from level 1 up: an eruption (3 and above) is a
    /// danger, heightened unrest (2) a caution, minor unrest (1) a notice.
    static func alert(for volcano: Volcano) -> ParkAlert? {
        guard volcano.level >= 1 else { return nil }
        let category = volcano.level >= 3 ? "Danger"
            : volcano.level == 2 ? "Caution" : "Information"
        return ParkAlert(
            id: "geonet:\(volcano.id):\(volcano.level)",
            title: "\(volcano.name): Volcanic Alert Level \(volcano.level)",
            description: [volcano.activity, volcano.hazards]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                + " Follow DOC's and the local authorities' advice on the ground.",
            category: category,
            url: pageURL,
            parkCode: nil,
            source: .geonet
        )
    }
}

extension AlertsCenter {
    /// GeoNet's levels for every New Zealand park given, from one fetch; at most hourly.
    /// A volcano is the park's when it lies inside the outline, or within ten kilometres
    /// of a park drawn without one.
    func refreshNewZealand(_ parks: [(Place, PlaceBoundary?)], force: Bool = false) async {
        guard !parks.isEmpty else { return }
        if !force, parks.allSatisfy({ isFresh($0.0.id) }) {
            return
        }
        let volcanoes: [GeoNetVolcanoes.Volcano]
        do {
            volcanoes = try await GeoNetVolcanoes.fetch()
        } catch {
            guard !isCancellation(error) else { return }
            for (place, _) in parks {
                markFailed(place.id)
            }
            return
        }
        for (place, boundary) in parks {
            let inside = volcanoes.filter { volcano in
                boundary.map { $0.contains(volcano.location) }
                    ?? (volcano.location.distance(to: place.centre) < 10000)
            }
            record(inside.compactMap(GeoNetVolcanoes.alert(for:)), for: place.id)
        }
    }
}
