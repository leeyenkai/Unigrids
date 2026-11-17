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
        }
    }

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
}
