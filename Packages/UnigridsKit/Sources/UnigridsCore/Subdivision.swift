import Foundation

/// A country's first-level division — a US state, a Japanese prefecture, a Norwegian
/// county — keyed `CC-nn` (ADR 0013).
///
/// US and Japanese codes are ISO 3166-2. Norway split three counties on 1 January 2024
/// and ISO 3166-2:NO has not caught up, so Norwegian codes are the official county numbers
/// in the same form (`NO-55` Troms); Svalbard keeps its ISO code, `NO-21`, though it lies
/// outside the county system.
///
/// Decoding an unknown code fails on purpose: `Place` drops it rather than showing a code
/// where a name should be, the mistake `USState`'s lenient decoder would make.
public struct Subdivision: Hashable, Sendable, Codable, Identifiable, Comparable {
    public let code: String
    public let name: String

    public var id: String {
        code
    }

    public var country: Country? {
        Country(rawValue: String(code.prefix(2)))
    }

    /// The state behind a US subdivision.
    public var usState: USState? {
        guard country == .unitedStates else { return nil }
        return USState.named(String(code.dropFirst(3)))
    }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    /// A US state as a subdivision: `UT` becomes `US-UT`.
    public init(state: USState) {
        self.init(code: "US-\(state.code)", name: state.name)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let code = try container.decode(String.self)
        guard let known = Subdivision.named(code) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unknown subdivision \(code)"
            )
        }
        self = known
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    public static func < (lhs: Subdivision, rhs: Subdivision) -> Bool {
        lhs.name < rhs.name
    }

    /// Look a subdivision up by code, case-insensitively. A bare two-letter code is read
    /// as a US state, the form saved map filters hold.
    public static func named(_ code: String) -> Subdivision? {
        let upper = code.uppercased()
        if upper.count == 2, let state = USState.named(upper) {
            return Subdivision(state: state)
        }
        return lookup[upper]
    }

    /// Every subdivision of a country, in code order.
    public static func all(in country: Country) -> [Subdivision] {
        switch country {
        case .unitedStates: USState.all.map(Subdivision.init(state:))
        case .japan: prefectures
        case .norway: norwegianCounties
        case .newZealand: newZealandRegions
        case .australia: australianStates
        case .canada: canadianProvinces
        }
    }

    /// The zone a place in this subdivision keeps when its record names none, for the
    /// countries that span several: Australia's states, Canada's provinces, and New
    /// Zealand's Chatham Islands (45 minutes ahead of the mainland).
    public var mainTimeZoneID: String? {
        Self.zones[code]
    }

    private static let zones: [String: String] = [
        "NZ-CIT": "Pacific/Chatham",
        "AU-NSW": "Australia/Sydney", "AU-VIC": "Australia/Melbourne",
        "AU-QLD": "Australia/Brisbane", "AU-SA": "Australia/Adelaide",
        "AU-WA": "Australia/Perth", "AU-TAS": "Australia/Hobart",
        "AU-NT": "Australia/Darwin", "AU-ACT": "Australia/Sydney",
        "AU-JBT": "Australia/Sydney", "AU-CX": "Indian/Christmas",
        "AU-CC": "Indian/Cocos", "AU-NF": "Pacific/Norfolk",
        "CA-BC": "America/Vancouver", "CA-AB": "America/Edmonton",
        "CA-SK": "America/Regina", "CA-MB": "America/Winnipeg",
        "CA-ON": "America/Toronto", "CA-QC": "America/Toronto",
        "CA-NB": "America/Moncton", "CA-NS": "America/Halifax",
        "CA-PE": "America/Halifax", "CA-NL": "America/St_Johns",
        "CA-YT": "America/Whitehorse", "CA-NT": "America/Yellowknife",
        "CA-NU": "America/Iqaluit",
    ]

    private static let lookup: [String: Subdivision] = Dictionary(
        uniqueKeysWithValues: Country.allCases.flatMap { all(in: $0) }.map { ($0.code, $0) }
    )

    /// Japan's 47 prefectures, in ISO 3166-2:JP order.
    public static let prefectures: [Subdivision] = [
        "Hokkaido", "Aomori", "Iwate", "Miyagi", "Akita", "Yamagata", "Fukushima",
        "Ibaraki", "Tochigi", "Gunma", "Saitama", "Chiba", "Tokyo", "Kanagawa",
        "Niigata", "Toyama", "Ishikawa", "Fukui", "Yamanashi", "Nagano", "Gifu",
        "Shizuoka", "Aichi", "Mie", "Shiga", "Kyoto", "Osaka", "Hyogo", "Nara",
        "Wakayama", "Tottori", "Shimane", "Okayama", "Hiroshima", "Yamaguchi",
        "Tokushima", "Kagawa", "Ehime", "Kochi", "Fukuoka", "Saga", "Nagasaki",
        "Kumamoto", "Oita", "Miyazaki", "Kagoshima", "Okinawa",
    ].enumerated().map { index, name in
        Subdivision(code: String(format: "JP-%02d", index + 1), name: name)
    }

    /// Norway's fifteen counties from 1 January 2024, by county number, and Svalbard.
    public static let norwegianCounties: [Subdivision] = [
        ("03", "Oslo"), ("11", "Rogaland"), ("15", "Møre og Romsdal"), ("18", "Nordland"),
        ("21", "Svalbard"), ("31", "Østfold"), ("32", "Akershus"), ("33", "Buskerud"),
        ("34", "Innlandet"), ("39", "Vestfold"), ("40", "Telemark"), ("42", "Agder"),
        ("46", "Vestland"), ("50", "Trøndelag"), ("55", "Troms"), ("56", "Finnmark"),
    ].map { Subdivision(code: "NO-\($0.0)", name: $0.1) }

    /// New Zealand's sixteen regions, in ISO 3166-2:NZ, and the Chatham Islands Territory.
    public static let newZealandRegions: [Subdivision] = [
        ("AUK", "Auckland"), ("BOP", "Bay of Plenty"), ("CAN", "Canterbury"),
        ("CIT", "Chatham Islands"), ("GIS", "Gisborne"), ("HKB", "Hawke's Bay"),
        ("MBH", "Marlborough"), ("MWT", "Manawatū-Whanganui"), ("NSN", "Nelson"),
        ("NTL", "Northland"), ("OTA", "Otago"), ("STL", "Southland"),
        ("TAS", "Tasman"), ("TKI", "Taranaki"), ("WGN", "Wellington"),
        ("WKO", "Waikato"), ("WTC", "West Coast"),
    ].map { Subdivision(code: "NZ-\($0.0)", name: $0.1) }

    /// Australia's six states and two mainland territories in ISO 3166-2:AU, then the
    /// territories ISO lists as countries of their own — Christmas Island, Cocos (Keeling)
    /// and Norfolk Island — and Jervis Bay, which has no code: Booderee lies there.
    public static let australianStates: [Subdivision] = [
        ("ACT", "Australian Capital Territory"), ("NSW", "New South Wales"),
        ("NT", "Northern Territory"), ("QLD", "Queensland"), ("SA", "South Australia"),
        ("TAS", "Tasmania"), ("VIC", "Victoria"), ("WA", "Western Australia"),
        ("CX", "Christmas Island"), ("CC", "Cocos (Keeling) Islands"),
        ("JBT", "Jervis Bay Territory"), ("NF", "Norfolk Island"),
    ].map { Subdivision(code: "AU-\($0.0)", name: $0.1) }

    /// Canada's ten provinces and three territories, in ISO 3166-2:CA.
    public static let canadianProvinces: [Subdivision] = [
        ("AB", "Alberta"), ("BC", "British Columbia"), ("MB", "Manitoba"),
        ("NB", "New Brunswick"), ("NL", "Newfoundland and Labrador"),
        ("NS", "Nova Scotia"), ("NT", "Northwest Territories"), ("NU", "Nunavut"),
        ("ON", "Ontario"), ("PE", "Prince Edward Island"), ("QC", "Quebec"),
        ("SK", "Saskatchewan"), ("YT", "Yukon"),
    ].map { Subdivision(code: "CA-\($0.0)", name: $0.1) }
}
