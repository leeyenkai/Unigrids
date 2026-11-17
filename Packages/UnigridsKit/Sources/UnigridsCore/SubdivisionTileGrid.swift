import Foundation

/// A country as a grid of equal squares, one per state, prefecture or county — the map
/// that fills in on the Stats tab (SPECIFICATION.md §11), for every country with parks.
///
/// The US layout is `USTileGrid`'s. Japan's and Norway's are Unigrids' own, drawn north up
/// and roughly where each division lies: Japan's 47 prefectures from Hokkaido at the top
/// right to Okinawa at the bottom left, labelled in kanji as Japanese tile maps are;
/// Norway's fifteen counties down the length of the country, Svalbard above them.
public struct SubdivisionTileGrid: Sendable {
    public struct Tile: Hashable, Sendable {
        /// The subdivision code: `US-UT`, `JP-01`, `NO-55`.
        public let code: String
        /// The text on the square: `UT`, `北海道`, `TRO`.
        public let label: String
        public let row: Int
        public let column: Int
    }

    public let columns: Int
    public let rows: Int
    public let tiles: [Tile]
    /// The language the labels are set in, for typesetting.
    public let labelLanguage: String

    public static func grid(for country: Country) -> SubdivisionTileGrid {
        switch country {
        case .unitedStates: unitedStates
        case .japan: japan
        case .norway: norway
        }
    }

    static let unitedStates = SubdivisionTileGrid(
        columns: USTileGrid.columns,
        rows: USTileGrid.rows,
        tiles: USTileGrid.tiles.map {
            Tile(code: "US-\($0.code)", label: $0.code, row: $0.row, column: $0.column)
        },
        labelLanguage: "en"
    )

    static let japan: SubdivisionTileGrid = {
        // [prefecture number, row, column], north up.
        let layout: [[Int]] = [
            [1, 0, 12],
            [2, 1, 11],
            [5, 2, 10], [3, 2, 11],
            [6, 3, 10], [4, 3, 11],
            [17, 4, 7], [16, 4, 8], [15, 4, 9], [7, 4, 10],
            [18, 5, 6], [21, 5, 7], [20, 5, 8], [10, 5, 9], [9, 5, 10], [8, 5, 11],
            [32, 6, 2], [31, 6, 3], [28, 6, 4], [26, 6, 5], [25, 6, 6], [23, 6, 7],
            [19, 6, 8], [11, 6, 9], [13, 6, 10], [12, 6, 11],
            [35, 7, 1], [34, 7, 2], [33, 7, 3], [27, 7, 4], [29, 7, 5], [24, 7, 6],
            [22, 7, 7], [14, 7, 9],
            [40, 8, 1], [38, 8, 3], [37, 8, 4], [30, 8, 5],
            [41, 9, 0], [44, 9, 1], [39, 9, 3], [36, 9, 4],
            [42, 10, 0], [43, 10, 1], [45, 10, 2],
            [47, 11, 0], [46, 11, 1],
        ]
        let kanji = [
            "北海道", "青森", "岩手", "宮城", "秋田", "山形", "福島", "茨城", "栃木", "群馬",
            "埼玉", "千葉", "東京", "神奈川", "新潟", "富山", "石川", "福井", "山梨", "長野",
            "岐阜", "静岡", "愛知", "三重", "滋賀", "京都", "大阪", "兵庫", "奈良", "和歌山",
            "鳥取", "島根", "岡山", "広島", "山口", "徳島", "香川", "愛媛", "高知", "福岡",
            "佐賀", "長崎", "熊本", "大分", "宮崎", "鹿児島", "沖縄",
        ]
        return SubdivisionTileGrid(
            columns: 13,
            rows: 12,
            tiles: layout.map { cell in
                Tile(
                    code: String(format: "JP-%02d", cell[0]),
                    label: kanji[cell[0] - 1],
                    row: cell[1],
                    column: cell[2]
                )
            },
            labelLanguage: "ja"
        )
    }()

    static let norway: SubdivisionTileGrid = {
        let layout: [Cell] = [
            Cell("21", "SVB", 0, 3),
            Cell("56", "FIN", 1, 3),
            Cell("55", "TRO", 2, 2),
            Cell("18", "NRD", 3, 1),
            Cell("50", "TRØ", 4, 1),
            Cell("15", "MRO", 5, 0), Cell("34", "INN", 5, 1),
            Cell("46", "VLD", 6, 0), Cell("33", "BUS", 6, 1), Cell("03", "OSL", 6, 2), Cell(
                "32",
                "AKE",
                6,
                3
            ),
            Cell("11", "ROG", 7, 0), Cell("40", "TEL", 7, 1), Cell("39", "VFO", 7, 2), Cell(
                "31",
                "ØST",
                7,
                3
            ),
            Cell("42", "AGD", 8, 1),
        ]
        return SubdivisionTileGrid(
            columns: 4,
            rows: 9,
            tiles: layout.map {
                Tile(code: "NO-\($0.number)", label: $0.label, row: $0.row, column: $0.column)
            },
            labelLanguage: "nb"
        )
    }()

    /// A Norwegian county's square, before it becomes a `Tile`.
    private struct Cell {
        let number: String
        let label: String
        let row: Int
        let column: Int

        init(_ number: String, _ label: String, _ row: Int, _ column: Int) {
            self.number = number
            self.label = label
            self.row = row
            self.column = column
        }
    }
}
