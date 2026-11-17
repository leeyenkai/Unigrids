import Foundation
import UnigridsCore

// Live warnings for Australia's parks (SPECIFICATION.md §10, ADR 0014): each state's
// fire service, read from its own public feed, and the NSW National Parks and Wildlife
// Service's park alerts. No key; every request is a fixed URL and says nothing about the
// reader. South Australia, the Northern Territory and the island territories publish no
// feed a request can read, so their parks claim no live warnings rather than an empty
// list that would read as all clear.

/// A fire or warning from a state's feed, before it is matched to a park.
struct FireIncident: Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    /// The national warning level, when the incident carries one.
    let level: String?
    let location: Coordinate
    let url: String
}

/// The state fire services' public feeds, and how each is read.
enum AustralianFires {
    enum Feed: String, CaseIterable, Sendable {
        case nswRFS, vicEmergency, qldFire, waDFES, tasAlert

        var url: URL? {
            let path = switch self {
            case .nswRFS: "https://www.rfs.nsw.gov.au/feeds/majorIncidents.json"
            case .vicEmergency: "https://emergency.vic.gov.au/public/events-geojson.json"
            case .qldFire: "https://publiccontent-gis-psba-qld-gov-au.s3.amazonaws.com/"
                + "content/Feeds/BushfireCurrentIncidents/bushfireAlert.json"
            case .waDFES: "https://api.emergency.wa.gov.au/v1/warnings"
            case .tasAlert: "https://alert.tas.gov.au/data/data.geojson"
            }
            return URL(string: path)
        }

        /// The feed that reports a state's fires. The ACT's parks border New South
        /// Wales, whose service lists the fires that reach them.
        static func covering(_ code: String) -> Feed? {
            switch code {
            case "AU-NSW", "AU-ACT": .nswRFS
            case "AU-VIC": .vicEmergency
            case "AU-QLD": .qldFire
            case "AU-WA": .waDFES
            case "AU-TAS": .tasAlert
            default: nil
            }
        }
    }

    static func fetch(_ feed: Feed) async throws -> [FireIncident] {
        guard let url = feed.url else { throw URLError(.badURL) }
        return try await incidents(from: AbroadFetch.data(url), feed: feed)
    }

    static func incidents(from data: Data, feed: Feed) throws -> [FireIncident] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        if feed == .waDFES {
            return (root["warnings"] as? [[String: Any]] ?? []).compactMap(waWarning)
        }
        let features = root["features"] as? [[String: Any]] ?? []
        return features.compactMap { feature in
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let geometry = feature["geometry"] as? [String: Any]
            return switch feed {
            case .nswRFS: nswIncident(properties, point(in: geometry))
            case .vicEmergency: vicIncident(properties, point(in: geometry))
            case .qldFire: qldWarning(properties, point(in: geometry))
            case .tasAlert: tasIncident(properties, point(in: geometry))
            case .waDFES: nil
            }
        }
    }

    /// NSW RFS: "ALERT LEVEL: Watch and Act" in the description; "Not Applicable" is a
    /// fire under control, kept as a notice.
    private static func nswIncident(_ props: [String: Any], _ at: Coordinate?) -> FireIncident? {
        guard let at, let title = props["title"] as? String else { return nil }
        let category = props["category"] as? String
        return FireIncident(
            id: "rfs:\(props["guid"] as? String ?? title)",
            title: title.capitalized,
            detail: plainText(props["description"] as? String ?? ""),
            level: category == "Not Applicable" ? nil : category,
            location: at,
            url: props["link"] as? String ?? "https://www.rfs.nsw.gov.au/fire-information/fires-near-me"
        )
    }

    /// Victoria: fires and planned burns from the state's emergency feed.
    private static func vicIncident(_ props: [String: Any], _ at: Coordinate?) -> FireIncident? {
        guard let at, let category = props["category1"] as? String,
              category.localizedCaseInsensitiveContains("fire")
              || category.localizedCaseInsensitiveContains("burn")
        else { return nil }
        let place = props["location"] as? String ?? props["sourceTitle"] as? String ?? ""
        return FireIncident(
            id: "vic:\(props["id"] as? String ?? place)",
            title: "\(category): \(place)",
            detail: [props["status"] as? String, props["sizeFmt"] as? String]
                .compactMap(\.self).joined(separator: ", "),
            level: nil,
            location: at,
            url: props["url"] as? String ?? "https://emergency.vic.gov.au"
        )
    }

    /// Queensland Fire's bushfire warnings, each with its level and point.
    private static func qldWarning(_ props: [String: Any], _ at: Coordinate?) -> FireIncident? {
        let latitude = Double(props["Latitude"] as? String ?? "")
        let longitude = Double(props["Longitude"] as? String ?? "")
        let point = zip([latitude].compactMap(\.self), [longitude].compactMap(\.self))
            .map { Coordinate(latitude: $0, longitude: $1) }
            .first
        guard let location = point ?? at, let title = props["WarningTitle"] as? String else {
            return nil
        }
        return FireIncident(
            id: "qld:\(props["UniqueID"] as? String ?? title)",
            title: title,
            detail: props["Header"] as? String ?? "",
            level: props["WarningLevel"] as? String,
            location: location,
            url: "https://www.fire.qld.gov.au/Current-Incidents"
        )
    }

    /// Western Australia's DFES warnings: "Bushfire Watch and Act" and the like.
    private static func waWarning(_ props: [String: Any]) -> FireIncident? {
        guard let location = props["location"] as? [String: Any],
              let latitude = location["latitude"] as? Double,
              let longitude = location["longitude"] as? Double
        else { return nil }
        let type = props["warning-type"] as? String ?? props["name"] as? String ?? "Warning"
        let level = ["Emergency Warning", "Watch and Act", "Advice"].first {
            type.localizedCaseInsensitiveContains($0)
        }
        return FireIncident(
            id: "dfes:\(props["id"] as? String ?? type)",
            title: props["title"] as? String ?? type,
            detail: plainText(props["alert-line"] as? String ?? ""),
            level: level,
            location: Coordinate(latitude: latitude, longitude: longitude),
            url: "https://www.emergency.wa.gov.au"
        )
    }

    /// TasALERT's incidents: bushfires with their status.
    private static func tasIncident(_ props: [String: Any], _ at: Coordinate?) -> FireIncident? {
        let location = (props["location"] as? [String: Any]).flatMap { place -> Coordinate? in
            guard let lat = place["lat"] as? Double, let lng = place["lng"] as? Double else {
                return nil
            }
            return Coordinate(latitude: lat, longitude: lng)
        }
        guard let point = location ?? at else { return nil }
        let title = props["title"] as? String ?? "Incident"
        let level = ["Emergency Warning", "Watch and Act", "Advice"].first {
            title.localizedCaseInsensitiveContains($0)
        }
        let address = (props["address"] as? String).map { ": \($0.capitalized)" } ?? ""
        return FireIncident(
            id: "tas:\(props["id"] as? String ?? title)",
            title: title + address,
            detail: [props["status"] as? String, plainText(props["bodyHtml"] as? String ?? "")]
                .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ". "),
            level: level,
            location: point,
            url: "https://alert.tas.gov.au"
        )
    }

    /// The first point a GeoJSON geometry holds, looking inside a collection.
    static func point(in geometry: [String: Any]?) -> Coordinate? {
        guard let geometry else { return nil }
        let pair = geometry["type"] as? String == "Point"
            ? geometry["coordinates"] as? [Double] ?? [] : []
        if pair.count >= 2 {
            return Coordinate(latitude: pair[1], longitude: pair[0])
        }
        for member in geometry["geometries"] as? [[String: Any]] ?? [] {
            if let point = point(in: member) {
                return point
            }
        }
        return nil
    }

    /// The Australian Warning System's three levels: an Emergency Warning is a danger,
    /// Watch and Act a caution, Advice and an incident without a warning a notice.
    static func alert(for incident: FireIncident) -> ParkAlert {
        let category = switch incident.level?.lowercased() {
        case "emergency warning": "Danger"
        case "watch and act": "Caution"
        default: "Information"
        }
        let level = incident.level.map { "\($0). " } ?? ""
        return ParkAlert(
            id: incident.id,
            title: incident.title,
            description: level + incident.detail,
            category: category,
            url: incident.url,
            parkCode: nil,
            source: .australianFeeds
        )
    }

    /// Inside the park, or within five kilometres of its edge: a fire across the boundary
    /// is the park's news too.
    static func touches(_ incident: FireIncident, place: Place, boundary: PlaceBoundary?) -> Bool {
        guard let boundary else { return incident.location.distance(to: place.centre) < 10000 }
        let box = boundary.extent
        let margin = 0.05
        guard incident.location.latitude >= box.south - margin,
              incident.location.latitude <= box.north + margin,
              incident.location.longitude >= box.west - margin,
              incident.location.longitude <= box.east + margin
        else { return false }
        if boundary.contains(incident.location) {
            return true
        }
        return boundary.polygons.contains { polygon in
            polygon.exterior.contains { $0.distance(to: incident.location) < 5000 }
        }
    }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " ([.,;:!?])", with: "$1", options: .regularExpression)
    }
}
