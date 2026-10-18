import Foundation

/// A stable identifier for a reference record.
///
/// Reference data is regenerated wholesale by the pipeline and replaced with each app
/// release, so user records must never point at it by name, coordinate or index — only by
/// the identifier the pipeline guarantees to keep. An identifier that stops resolving is a
/// recoverable condition, not a crash: the log still shows the visit, with a placeholder
/// in the place's position.
///
/// The textual form is a short, readable slug prefixed by kind, for example
/// `np-zion`, `poi-zion-angels-landing`, `trail-zion-narrows-bottom-up`.
public struct UnigridsID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

extension UnigridsID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension UnigridsID: Comparable {
    public static func < (lhs: UnigridsID, rhs: UnigridsID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
