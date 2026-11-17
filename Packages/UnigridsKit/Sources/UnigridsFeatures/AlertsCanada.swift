import Foundation
import UnigridsCore

// Live warnings for Canada's parks (SPECIFICATION.md §10, ADR 0014): Environment and
// Climate Change Canada's weather alerts from MSC GeoMet's open API, and Avalanche
// Canada's forecast for the mountain parks of British Columbia, Alberta and Yukon. No
// key; each request carries a park's box or point and nothing about the reader.

/// Environment and Climate Change Canada's alerts in force over a park: warnings, watches,
/// advisories and statements, from the MSC GeoMet `weather-alerts` collection.
enum ECCCAlerts {
    struct Properties: Decodable {
        let alert_code: String? // swiftlint:disable:this identifier_name
        let alert_type: String // swiftlint:disable:this identifier_name
        let alert_name_en: String // swiftlint:disable:this identifier_name
        let alert_text_en: String? // swiftlint:disable:this identifier_name
        let risk_colour_en: String? // swiftlint:disable:this identifier_name
        let feature_name_en: String? // swiftlint:disable:this identifier_name
        let feature_id: String? // swiftlint:disable:this identifier_name
        let status_en: String? // swiftlint:disable:this identifier_name
        let expiration_datetime: String? // swiftlint:disable:this identifier_name
    }

    static let pageURL = "https://weather.gc.ca/?layers=alert"

    /// The alerts whose areas cross `box`, the park's extent.
    static func alerts(in box: BoundingBox, now: Date = Date()) async throws -> [ParkAlert] {
        let bbox = [box.west, box.south, box.east, box.north]
            .map { String(format: "%.4f", $0) }
            .joined(separator: ",")
        let path = "https://api.weather.gc.ca/collections/weather-alerts/items?f=json"
            + "&skipGeometry=true&limit=200&bbox=\(bbox)"
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        return try await alerts(from: AbroadFetch.data(url), now: now)
    }

    static func alerts(from data: Data, now: Date = Date()) throws -> [ParkAlert] {
        struct Feature: Decodable {
            let properties: Properties
        }
        struct Collection: Decodable {
            let features: [Lossy<Feature>]
        }
        let features = try lossyValues(JSONDecoder().decode(Collection.self, from: data).features)
        // One alert can cover several forecast areas inside a big park; it is shown once.
        var seen = Set<String>()
        return features.compactMap { feature in
            guard let alert = alert(for: feature.properties, now: now),
                  seen.insert(alert.title).inserted
            else { return nil }
            return alert
        }
    }

    /// A warning in orange or red is a danger, one in yellow and every watch a caution,
    /// an advisory or statement information. An ended, cancelled or expired alert is none.
    static func alert(for alert: Properties, now: Date = Date()) -> ParkAlert? {
        let status = alert.status_en?.lowercased() ?? ""
        guard status != "ended", status != "cancelled" else { return nil }
        if let expiry = alert.expiration_datetime.flatMap(parseDate), expiry < now {
            return nil
        }
        let type = alert.alert_type.lowercased()
        let colour = alert.risk_colour_en?.lowercased()
        let category = switch type {
        case "warning": colour == "orange" || colour == "red" ? "Danger" : "Caution"
        case "watch": "Caution"
        default: "Information"
        }
        let name = alert.alert_name_en.prefix(1).uppercased() + alert.alert_name_en.dropFirst()
        let area = alert.feature_name_en.map { ": \($0)" } ?? ""
        return ParkAlert(
            id: "eccc:\(alert.feature_id ?? ""):\(alert.alert_code ?? type)",
            title: name + area,
            description: alert.alert_text_en ?? "",
            category: category,
            url: pageURL,
            parkCode: nil,
            source: .eccc
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? style.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// Avalanche Canada's forecast for the region a point lies in. Its regions cover the
/// mountains of British Columbia, Alberta and Yukon; elsewhere the answer is empty.
enum AvalancheCanada {
    struct Product: Decodable {
        struct Report: Decodable {
            let id: String
            let title: String?
            let highlights: String?
            let dangerRatings: [Day]?
        }

        struct Day: Decodable {
            let ratings: [String: Elevation]
        }

        /// One elevation band's rating: `{"rating": {"value": "considerable"}}`.
        struct Elevation: Decodable {
            let rating: Rating
        }

        struct Rating: Decodable {
            let value: String
        }

        let url: String?
        let report: Report
    }

    /// The provinces and territory whose parks Avalanche Canada's regions can reach.
    static let regions: Set<String> = ["CA-BC", "CA-AB", "CA-YT"]

    static func alerts(at point: Coordinate) async throws -> [ParkAlert] {
        let path = "https://api.avalanche.ca/forecasts/en/products/point?"
            + String(format: "lat=%.4f&long=%.4f", point.latitude, point.longitude)
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        let product = try await JSONDecoder().decode(Product.self, from: AbroadFetch.data(url))
        return alert(for: product).map { [$0] } ?? []
    }

    /// The highest of today's three elevation bands sets the level, on the North American
    /// danger scale: high and extreme are dangers, considerable a caution, low and
    /// moderate information. Early season, spring and no rating make no alert.
    static func alert(for product: Product) -> ParkAlert? {
        guard !product.report.id.isEmpty,
              let today = product.report.dangerRatings?.first
        else { return nil }
        let scale = ["low": 1, "moderate": 2, "considerable": 3, "high": 4, "extreme": 5]
        guard let level = today.ratings.values.compactMap({ scale[$0.rating.value] }).max()
        else { return nil }
        let names = [1: "low", 2: "moderate", 3: "considerable", 4: "high", 5: "extreme"]
        let category = level >= 4 ? "Danger" : level == 3 ? "Caution" : "Information"
        let region = product.report.title.map { ", in \($0)" } ?? ""
        return ParkAlert(
            id: "avcan:\(product.report.id):\(level)",
            title: "Avalanche danger \(level), \(names[level] ?? "")\(region)",
            description: plainText(product.report.highlights ?? ""),
            category: category,
            url: product.url?.isEmpty == false ? product.url ?? "" : "https://avalanche.ca",
            parkCode: nil,
            source: .avalancheCanada
        )
    }

    /// The forecast's highlights without their HTML tags.
    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .replacingOccurrences(of: " ([.,;:!?])", with: "$1", options: .regularExpression)
    }
}

extension AlertsCenter {
    /// Environment Canada's alerts over each park given, and Avalanche Canada's forecast
    /// for those in its regions, a few parks at a time; each park at most hourly.
    func refreshCanada(_ parks: [(Place, PlaceBoundary?)], force: Bool = false) async {
        let stale = parks.filter { force || !isFresh($0.0.id) }
        for start in stride(from: 0, to: stale.count, by: 4) {
            let batch = stale[start ..< min(start + 4, stale.count)]
            let answers = await withTaskGroup(of: (UnigridsID, [ParkAlert]?).self) { group in
                for (park, boundary) in batch {
                    let box = boundary?.extent ?? BoundingBox(
                        south: park.centre.latitude - 0.1, west: park.centre.longitude - 0.1,
                        north: park.centre.latitude + 0.1, east: park.centre.longitude + 0.1
                    )
                    let mountains = park.subdivisions.contains {
                        AvalancheCanada.regions.contains($0.code)
                    }
                    let (id, centre) = (park.id, park.centre)
                    group.addTask {
                        do {
                            var alerts = try await ECCCAlerts.alerts(in: box)
                            if mountains {
                                alerts += await (try? AvalancheCanada.alerts(at: centre)) ?? []
                            }
                            return (id, alerts)
                        } catch {
                            return (id, nil)
                        }
                    }
                }
                var answers: [(UnigridsID, [ParkAlert]?)] = []
                for await answer in group {
                    answers.append(answer)
                }
                return answers
            }
            // Leaving the map is not Environment Canada failing.
            guard !Task.isCancelled else { return }
            for (id, alerts) in answers {
                if let alerts {
                    record(alerts, for: id)
                } else {
                    markFailed(id)
                }
            }
        }
    }
}
