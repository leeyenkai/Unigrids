import Foundation

/// A US state, federal district or territory, by its USPS code.
///
/// Territories are first-class: the specification (§2) puts all US territories on the map
/// and in the stats, so nothing here filters them out.
public struct USState: Hashable, Sendable, Codable, Identifiable, Comparable {
    public let code: String
    public let name: String
    public let isTerritory: Bool

    public var id: String {
        code
    }

    public init(code: String, name: String, isTerritory: Bool = false) {
        self.code = code
        self.name = name
        self.isTerritory = isTerritory
    }

    public init(from decoder: any Decoder) throws {
        let code = try decoder.singleValueContainer().decode(String.self)
        self = USState.named(code) ?? USState(code: code, name: code)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }

    public static func < (lhs: USState, rhs: USState) -> Bool {
        lhs.name < rhs.name
    }

    /// Look up a state by USPS code, case-insensitively.
    public static func named(_ code: String) -> USState? {
        lookup[code.uppercased()]
    }

    private static let lookup: [String: USState] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )

    /// The 50 states, the District of Columbia and the five inhabited territories.
    public static let all: [USState] = [
        USState(code: "AL", name: "Alabama"),
        USState(code: "AK", name: "Alaska"),
        USState(code: "AZ", name: "Arizona"),
        USState(code: "AR", name: "Arkansas"),
        USState(code: "CA", name: "California"),
        USState(code: "CO", name: "Colorado"),
        USState(code: "CT", name: "Connecticut"),
        USState(code: "DE", name: "Delaware"),
        USState(code: "DC", name: "District of Columbia"),
        USState(code: "FL", name: "Florida"),
        USState(code: "GA", name: "Georgia"),
        USState(code: "HI", name: "Hawaii"),
        USState(code: "ID", name: "Idaho"),
        USState(code: "IL", name: "Illinois"),
        USState(code: "IN", name: "Indiana"),
        USState(code: "IA", name: "Iowa"),
        USState(code: "KS", name: "Kansas"),
        USState(code: "KY", name: "Kentucky"),
        USState(code: "LA", name: "Louisiana"),
        USState(code: "ME", name: "Maine"),
        USState(code: "MD", name: "Maryland"),
        USState(code: "MA", name: "Massachusetts"),
        USState(code: "MI", name: "Michigan"),
        USState(code: "MN", name: "Minnesota"),
        USState(code: "MS", name: "Mississippi"),
        USState(code: "MO", name: "Missouri"),
        USState(code: "MT", name: "Montana"),
        USState(code: "NE", name: "Nebraska"),
        USState(code: "NV", name: "Nevada"),
        USState(code: "NH", name: "New Hampshire"),
        USState(code: "NJ", name: "New Jersey"),
        USState(code: "NM", name: "New Mexico"),
        USState(code: "NY", name: "New York"),
        USState(code: "NC", name: "North Carolina"),
        USState(code: "ND", name: "North Dakota"),
        USState(code: "OH", name: "Ohio"),
        USState(code: "OK", name: "Oklahoma"),
        USState(code: "OR", name: "Oregon"),
        USState(code: "PA", name: "Pennsylvania"),
        USState(code: "RI", name: "Rhode Island"),
        USState(code: "SC", name: "South Carolina"),
        USState(code: "SD", name: "South Dakota"),
        USState(code: "TN", name: "Tennessee"),
        USState(code: "TX", name: "Texas"),
        USState(code: "UT", name: "Utah"),
        USState(code: "VT", name: "Vermont"),
        USState(code: "VA", name: "Virginia"),
        USState(code: "WA", name: "Washington"),
        USState(code: "WV", name: "West Virginia"),
        USState(code: "WI", name: "Wisconsin"),
        USState(code: "WY", name: "Wyoming"),
        USState(code: "AS", name: "American Samoa", isTerritory: true),
        USState(code: "GU", name: "Guam", isTerritory: true),
        USState(code: "MP", name: "Northern Mariana Islands", isTerritory: true),
        USState(code: "PR", name: "Puerto Rico", isTerritory: true),
        USState(code: "VI", name: "US Virgin Islands", isTerritory: true),
    ]
}
