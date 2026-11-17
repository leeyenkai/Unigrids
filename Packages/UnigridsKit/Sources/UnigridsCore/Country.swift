import Foundation

/// The country a place is in, and so the national park system it belongs to (ADR 0013).
///
/// Every place decodes as American unless its record says otherwise: the US came first,
/// and every identifier minted before other countries arrived is a US one.
public enum Country: String, CaseIterable, Sendable, Codable, Identifiable {
    case unitedStates = "US"
    case japan = "JP"
    case norway = "NO"

    public var id: String {
        rawValue
    }

    /// The ISO 3166-1 alpha-2 code.
    public var code: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .unitedStates: "United States"
        case .japan: "Japan"
        case .norway: "Norway"
        }
    }

    /// The body that designates the country's national parks, for credits and the
    /// non-affiliation line.
    public var parkAuthority: String {
        switch self {
        case .unitedStates: "National Park Service"
        case .japan: "Ministry of the Environment"
        case .norway: "Norwegian Environment Agency"
        }
    }

    /// What the country calls its first-level divisions, singular and plural.
    public var subdivisionNoun: (singular: String, plural: String) {
        switch self {
        case .unitedStates: ("state", "states")
        case .japan: ("prefecture", "prefectures")
        case .norway: ("county", "counties")
        }
    }

    /// The zone most of the country keeps, for a place whose record names none. Nil for
    /// the US, which spans six and falls back by state instead.
    public var mainTimeZoneID: String? {
        switch self {
        case .unitedStates: nil
        case .japan: "Asia/Tokyo"
        case .norway: "Europe/Oslo"
        }
    }

    /// The first component of the identifiers this country's places carry. Nil for the
    /// US, whose identifiers predate namespacing (`np-zion`, `nps-arpo`).
    public var identifierNamespace: String? {
        switch self {
        case .unitedStates: nil
        case .japan: "jp"
        case .norway: "no"
        }
    }

    /// The country of a record known only by its identifier — a stamp or visit whose
    /// place has left the dataset.
    ///
    /// Places abroad are namespaced (`jp-np-shiretoko`), and their sights and trails carry
    /// the namespace after their kind (`poi-jp-…`, `trail-no-…`). Anything else was minted
    /// for the US.
    public static func inferred(from id: UnigridsID) -> Country {
        var parts = id.rawValue.split(separator: "-", maxSplits: 2)[...]
        if let kind = parts.first, kind == "poi" || kind == "trail" {
            parts = parts.dropFirst()
        }
        guard let namespace = parts.first.map(String.init) else { return .unitedStates }
        return allCases.first { $0.identifierNamespace == namespace } ?? .unitedStates
    }
}

/// A place's name in its own language: 知床国立公園, Jotunheimen nasjonalpark, an official
/// Sámi name. Shown beneath the English name and searched alongside it.
public struct LocalName: Hashable, Sendable, Codable {
    /// A BCP 47 language tag: `ja`, `nb`, `nn`, `se`, `smj`, `sma`.
    public let language: String
    public let text: String

    public init(language: String, text: String) {
        self.language = language
        self.text = text
    }
}

extension Place {
    /// Where the place is, beneath its name: "Utah", "Tennessee · North Carolina",
    /// "Hokkaido". A US place reads exactly as `statesDescription` always has. Abroad, a
    /// place across more than three divisions gives the count instead — Setonaikai lies in
    /// eleven prefectures.
    public var regionLine: String {
        guard country != .unitedStates else { return statesDescription }
        guard subdivisions.count > 3 else {
            return subdivisions.map(\.name).joined(separator: " · ")
        }
        return "\(subdivisions.count) \(country.subdivisionNoun.plural)"
    }

    /// The first of the place's own-language names that is not just its English name,
    /// for the line beneath the title: 知床国立公園, Rondane nasjonalpark.
    public var leadLocalName: LocalName? {
        localNames.first { SearchText.fold($0.text) != SearchText.fold(name) }
    }

    /// The band's second line: "Utah" at home, "Hokkaido · Japan" abroad.
    public var bandLine: String {
        country == .unitedStates ? statesDescription
            : [regionLine, country.name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The foot of a cancellation: the state's postal code at home, as it always was;
    /// the prefecture or county abroad.
    public var stampMark: String {
        switch country {
        case .unitedStates: states.first?.code ?? "US"
        case .japan, .norway: subdivisions.first?.name ?? country.name
        }
    }

    /// Whether the place belongs to its country's national park system, and so has a
    /// slot in the passport rather than a place in "Beyond" once stamped: any NPS site at
    /// home, a national park abroad.
    public var isNationalParkSystemSite: Bool {
        switch country {
        case .unitedStates: agency == .nps
        case .japan, .norway: kind == .nationalPark
        }
    }
}

/// How many states, prefectures and counties a set of places covers, and what to call
/// them: "States" while every place is American, as a trip's figures always said;
/// "Regions" once one is abroad.
public enum RegionFigure {
    public static func of(_ places: [Place]) -> (count: Int, label: String) {
        let count = Set(places.flatMap { $0.subdivisions.map(\.code) }).count
        let american = places.allSatisfy { $0.country == .unitedStates }
        let noun = american ? (count == 1 ? "State" : "States") :
            (count == 1 ? "Region" : "Regions")
        return (count, noun)
    }
}
