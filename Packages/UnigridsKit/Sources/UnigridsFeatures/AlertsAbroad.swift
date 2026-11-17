import Foundation
import UnigridsCore

/// Who posted an alert, for its credit line and its link. The NPS today; the warning
/// services of other countries join as their places do (SPECIFICATION.md §10).
enum AlertSource: String, Hashable, Sendable {
    case nps
    /// The Japan Meteorological Agency's eruption warnings (`AlertsAbroad.swift`).
    case jma
    /// The Norwegian Avalanche Warning Service, Varsom, run by NVE.
    case varsom

    /// "Live from the National Park Service".
    var name: String {
        switch self {
        case .nps: "the National Park Service"
        case .jma: "the Japan Meteorological Agency"
        case .varsom: "Varsom, the Norwegian Avalanche Warning Service (NVE, NLOD)"
        }
    }

    var unreachable: String {
        switch self {
        case .nps: "The NPS could not be reached. Alerts need a connection."
        case .jma: "JMA could not be reached. Warnings need a connection."
        case .varsom: "Varsom could not be reached. Warnings need a connection."
        }
    }

    var linkLabel: String {
        switch self {
        case .nps: "More on nps.gov"
        case .jma: "More on jma.go.jp"
        case .varsom: "More on varsom.no"
        }
    }

    /// What the panel says when nothing is posted, in each service's own terms.
    var noneText: String {
        switch self {
        case .nps: "No alerts posted right now."
        case .jma: "JMA lists no eruption warning for a volcano in this park. That is not "
            + "a statement that a volcano is quiet: check JMA and local notices before you "
            + "climb."
        case .varsom: "No avalanche warning is in force here today. Varsom forecasts the "
            + "mainland from December to May, and Svalbard's Nordenskiöld Land in winter."
        }
    }
}

// Live warnings abroad, from each country's own warning service (SPECIFICATION.md §10,
// docs/sources-japan-norway.md): the Japan Meteorological Agency's eruption warnings for
// the volcanoes inside a park, and the Norwegian avalanche forecast (Varsom, NVE) where
// the park lies. Neither needs a key, and neither request carries anything about the
// reader: a fixed URL, or a park's own coordinates.

/// The Japan Meteorological Agency's current eruption warnings and the volcanoes it
/// monitors, both from its own site.
///
/// JMA lists only volcanoes under a warning. A volcano absent from the list has no
/// warning JMA states — which is not the same as "Level 1" — so the app never shows a
/// level the agency has not given, and relays its text unchanged beside the English name.
enum JMAVolcanoes {
    struct Volcano: Hashable, Sendable {
        let code: String
        let nameEnglish: String
        let nameJapanese: String
        let location: Coordinate
    }

    struct Warning: Hashable, Sendable {
        let volcanoCode: String
        /// As JMA writes it: "レベル２（火口周辺規制）", "火口周辺危険".
        let levelText: String
        let reported: Date?
    }

    static let listURL = URL(string: "https://www.jma.go.jp/bosai/volcano/const/volcano_list.json")
    static let warningsURL = URL(string: "https://www.jma.go.jp/bosai/volcano/data/warning.json")
    static let pageURL = "https://www.jma.go.jp/bosai/map.html#contents=volcano"

    /// The volcanoes and the warnings in force, fetched together.
    static func fetch() async throws -> (volcanoes: [Volcano], warnings: [Warning]) {
        guard let listURL, let warningsURL else { throw URLError(.badURL) }
        async let list = AbroadFetch.data(listURL)
        async let current = AbroadFetch.data(warningsURL)
        return try await (volcanoes(from: list), warnings(from: current))
    }

    static func volcanoes(from data: Data) throws -> [Volcano] {
        struct Row: Decodable {
            let code: String
            let latlon: [String]
            let name_jp: String // swiftlint:disable:this identifier_name
            let name_en: String // swiftlint:disable:this identifier_name
        }
        return try lossyValues(JSONDecoder().decode([Lossy<Row>].self, from: data))
            .compactMap { row in
                guard row.latlon.count == 2, let lat = Double(row.latlon[0]),
                      let lon = Double(row.latlon[1]) else { return nil }
                return Volcano(
                    code: row.code,
                    nameEnglish: row.name_en,
                    nameJapanese: row.name_jp,
                    location: Coordinate(latitude: lat, longitude: lon)
                )
            }
    }

    /// The warning for each volcano, from the entries' "対象火山" (target volcano) items.
    static func warnings(from data: Data) throws -> [Warning] {
        struct Area: Decodable { let code: String }
        struct Item: Decodable {
            let name: String
            let areas: [Area]
        }
        struct Info: Decodable {
            let type: String
            let items: [Item]
        }
        struct Report: Decodable {
            let reportDatetime: String?
            let volcanoInfos: [Info]
        }
        let reports = try lossyValues(JSONDecoder().decode([Lossy<Report>].self, from: data))
        let dates = ISO8601DateFormatter()
        return reports.flatMap { report in
            report.volcanoInfos
                .filter { $0.type.contains("対象火山") }
                .flatMap(\.items)
                .flatMap { item in
                    item.areas.map {
                        Warning(
                            volcanoCode: $0.code,
                            levelText: item.name,
                            reported: report.reportDatetime.flatMap(dates.date(from:))
                        )
                    }
                }
        }
    }

    /// The level JMA gives, read from its own wording, with the English name the agency
    /// uses for it; nil for a warning without a numbered level.
    static func level(of text: String) -> (number: Int, english: String)? {
        let digits = [
            "１": 1,
            "２": 2,
            "３": 3,
            "４": 4,
            "５": 5,
            "1": 1,
            "2": 2,
            "3": 3,
            "4": 4,
            "5": 5,
        ]
        guard text.contains("レベル"),
              let number = digits.first(where: { text.contains($0.key) })?.value
        else { return nil }
        let english = [
            1: "Potential for increased activity",
            2: "Do not approach the crater",
            3: "Do not approach the volcano",
            4: "Prepare to evacuate",
            5: "Evacuate",
        ]
        return (number, "Level \(number): \(english[number] ?? "")")
    }

    /// The alert a park shows for one of its volcanoes' warnings. Levels 4 and 5 and a
    /// warning for where people live are dangers; a closed crater or mountain is a closure.
    static func alert(for warning: Warning, volcano: Volcano) -> ParkAlert {
        let level = level(of: warning.levelText)
        let category: String = if let level {
            level.number >= 4 ? "Danger" : level.number >= 2 ? "Park Closure" : "Information"
        } else if warning.levelText.contains("居住地域") {
            "Danger"
        } else {
            "Park Closure"
        }
        let reported = warning.reported.map {
            " Issued \($0.formatted(date: .abbreviated, time: .omitted))."
        } ?? ""
        return ParkAlert(
            id: "jma:\(volcano.code):\(warning.levelText)",
            title: "\(volcano.nameEnglish) (\(volcano.nameJapanese)): "
                + (level?.english ?? "eruption warning"),
            description: "JMA: \(warning.levelText).\(reported) Follow the local "
                + "authorities' restrictions on the ground.",
            category: category,
            url: pageURL,
            parkCode: nil,
            source: .jma
        )
    }
}

/// The Norwegian Avalanche Warning Service's forecast for a point, from NVE's open API.
enum VarsomAvalanche {
    struct Forecast: Decodable {
        let RegionId: Int // swiftlint:disable:this identifier_name
        let RegionName: String // swiftlint:disable:this identifier_name
        let DangerLevel: String // swiftlint:disable:this identifier_name
        let ValidFrom: String // swiftlint:disable:this identifier_name
        let MainText: String? // swiftlint:disable:this identifier_name
    }

    static let pageURL = "https://www.varsom.no/en/avalanche-bulletins/"

    /// Today's forecast where `point` lies, in English. Outside the season (December to
    /// May on the mainland) the region carries no rating, and no alert results.
    static func alerts(at point: Coordinate, on day: Date = Date()) async throws -> [ParkAlert] {
        let date = forecastDay(day)
        let path = "https://api01.nve.no/hydrology/forecast/avalanche/v6.3.2/api/"
            + "AvalancheWarningByCoordinates/Simple/"
            + String(format: "%.4f/%.4f", point.latitude, point.longitude)
            + "/2/\(date)/\(date)"
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        let data = try await AbroadFetch.data(url)
        let forecasts = try lossyValues(JSONDecoder().decode([Lossy<Forecast>].self, from: data))
        return forecasts.compactMap(alert(for:))
    }

    /// The forecast day as Varsom names it: Norway's date, not UTC's, so half past
    /// midnight in Oslo asks for today's forecast rather than yesterday's.
    static func forecastDay(_ day: Date) -> String {
        let oslo = TimeZone(identifier: "Europe/Oslo") ?? .gmt
        return day.formatted(Date.ISO8601FormatStyle(timeZone: oslo).year().month().day())
    }

    /// Danger levels 4 and 5 are dangers, 3 a caution, 2 and below information; 0 is no
    /// rating and makes no alert.
    static func alert(for forecast: Forecast) -> ParkAlert? {
        guard let level = Int(forecast.DangerLevel), level > 0 else { return nil }
        let category = level >= 4 ? "Danger" : level == 3 ? "Caution" : "Information"
        let names = [1: "low", 2: "moderate", 3: "considerable", 4: "high", 5: "very high"]
        return ParkAlert(
            id: "varsom:\(forecast.RegionId):\(forecast.ValidFrom)",
            title: "Avalanche danger \(level), \(names[level] ?? ""), in \(forecast.RegionName)",
            description: forecast.MainText ?? "",
            category: category,
            url: pageURL,
            parkCode: nil,
            source: .varsom
        )
    }
}

/// A plain GET with a 200 check and an app-only User-Agent.
enum AbroadFetch {
    /// Names the app and nothing about the reader.
    static let userAgent = "Unigrids (iOS and macOS app)"

    static func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
