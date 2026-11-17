import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// Stats for more than one country (ADR 0013): national parks and the map that fills in,
// country by country. With only the US in the data these draw exactly what they always
// did.

extension Country {
    /// The heading over a country's tile map.
    var subdivisionsTitle: String {
        switch self {
        case .unitedStates: "States and territories"
        case .japan: "Prefectures"
        case .norway: "Counties and Svalbard"
        case .newZealand: "Regions"
        case .australia: "States and territories"
        case .canada: "Provinces and territories"
        }
    }
}

/// A country's states, prefectures or counties as equal squares, filled where the reader
/// has been.
struct SubdivisionTileMap: View {
    @Environment(\.unigrid) private var style
    let grid: SubdivisionTileGrid
    let visited: Set<String>

    /// The largest a square gets: about the US map's, so Norway's four columns do not
    /// print at twice the size of Japan's thirteen.
    private let largest: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 3
            let side = min(
                (proxy.size.width - gap * CGFloat(grid.columns - 1)) / CGFloat(grid.columns),
                largest
            )
            ZStack(alignment: .topLeading) {
                ForEach(grid.tiles, id: \.code) { tile in
                    SubdivisionTile(
                        tile: tile,
                        language: grid.labelLanguage,
                        side: side,
                        isVisited: visited.contains(tile.code)
                    )
                    .offset(
                        x: CGFloat(tile.column) * (side + gap),
                        y: CGFloat(tile.row) * (side + gap)
                    )
                }
            }
        }
        .aspectRatio(CGFloat(grid.columns) / CGFloat(grid.rows), contentMode: .fit)
        .frame(maxWidth: largest * CGFloat(grid.columns) + 3 * CGFloat(grid.columns - 1))
    }
}

private struct SubdivisionTile: View {
    @Environment(\.unigrid) private var style
    let tile: SubdivisionTileGrid.Tile
    let language: String
    let side: CGFloat
    let isVisited: Bool

    var body: some View {
        Text(tile.label)
            .font(.custom("HelveticaNeue-Bold", size: max(side * 0.26, 7)))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .typesettingLanguage(Locale.Language(identifier: language))
            .foregroundStyle(isVisited ? style.onAccent : style.inkSecondary)
            .frame(width: side, height: side)
            .background(isVisited ? style.accent : Color.clear)
            .overlay {
                Rectangle().strokeBorder(isVisited ? style.accent : style.rule, lineWidth: 1)
            }
            .accessibilityLabel(
                "\(Subdivision.named(tile.code)?.name ?? tile.label), "
                    + (isVisited ? "visited" : "not visited")
            )
    }
}

/// The national park grids, one per country, under the overall figure — shown when the
/// data holds more than one country.
struct NationalParksByCountry: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let figures: [StatsReport.CountryCompletion]
    let index: VisitIndex

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Kicker(figure.country.name)
                        Spacer()
                        Text(figure.completion.description)
                            .font(UnigridStyle.dataLabel)
                            .foregroundStyle(style.inkSecondary)
                            .monospacedDigit()
                    }
                    ParkGrid(
                        parks: store.nationalParks.filter { $0.country == figure.country },
                        index: index,
                        side: 22
                    )
                }
            }
            // The homage the app is built on: the idea began at Yellowstone.
            Text("Yellowstone, in 1872, was the first national park. Canada set aside Banff "
                + "in 1885, New Zealand made Tongariro its first in 1894, Japan named its "
                + "first in 1934, and Norway in 1962.")
                .font(UnigridStyle.proseSmall)
                .foregroundStyle(style.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The map that fills in, for each country in the data: the US's as it always was, then
/// Japan's prefectures and Norway's counties.
struct SubdivisionMapsSection: View {
    @Environment(\.referenceStore) private var store
    let report: StatsReport
    let visits: [Visit]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(report.subdivisionsByCountry) { figure in
                VStack(alignment: .leading, spacing: 12) {
                    if figure.country == .unitedStates {
                        SectionHead(
                            figure.country.subdivisionsTitle,
                            detail: report.states.description
                        )
                        USTileMap(visited: Set(report.visitedStates.map(\.code)))
                    } else {
                        SectionHead(
                            figure.country.subdivisionsTitle,
                            detail: figure.completion.description
                        )
                        SubdivisionTileMap(
                            grid: .grid(for: figure.country),
                            visited: visited(in: figure.country)
                        )
                    }
                }
            }
        }
    }

    private func visited(in country: Country) -> Set<String> {
        Set(
            Set(visits.map(\.place)).compactMap(store.place)
                .filter { $0.country == country }
                .flatMap(\.subdivisions)
                .map(\.code)
        )
    }
}
