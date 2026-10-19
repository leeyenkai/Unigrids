import Foundation

/// The United States as a grid of equal squares, one per state — the "US map that fills
/// in" of SPECIFICATION.md §11.
///
/// A tile grid rather than drawn borders: every state gets the same weight, Rhode Island
/// is as tappable as Texas, and the squares are the same squares the rest of the app is
/// built from. The arrangement is the widely used eleven-column layout; the territories
/// sit on a row of their own beneath it.
public enum USTileGrid {
    public struct Tile: Hashable, Sendable {
        public let code: String
        public let row: Int
        public let column: Int
    }

    public static let columns = 11
    public static let rows = 9

    public static let tiles: [Tile] = {
        let layout: [[String?]] = [
            ["AK", nil, nil, nil, nil, nil, nil, nil, nil, nil, "ME"],
            [nil, nil, nil, nil, nil, nil, nil, nil, nil, "VT", "NH"],
            ["WA", "ID", "MT", "ND", "MN", "IL", "WI", "MI", "NY", "RI", "MA"],
            ["OR", "NV", "WY", "SD", "IA", "IN", "OH", "PA", "NJ", "CT", nil],
            ["CA", "UT", "CO", "NE", "MO", "KY", "WV", "VA", "MD", "DE", nil],
            [nil, "AZ", "NM", "KS", "AR", "TN", "NC", "SC", "DC", nil, nil],
            [nil, nil, nil, "OK", "LA", "MS", "AL", "GA", nil, nil, nil],
            ["HI", nil, nil, "TX", nil, nil, nil, nil, "FL", nil, nil],
            ["GU", "MP", "AS", nil, nil, nil, nil, nil, "PR", "VI", nil],
        ]
        return layout.enumerated().flatMap { row, codes in
            codes.enumerated().compactMap { column, code in
                code.map { Tile(code: $0, row: row, column: column) }
            }
        }
    }()
}
