import Charts
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The Stats tab's sections beyond completion: every kind of place visited, visits by
// month, and the weather family (SPECIFICATION.md §11).

/// Every kind of place the reader has been, by its pin: the map key, filled in.
struct KindsOfPlaceSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let visits: [Visit]

    var body: some View {
        let visited = Set(visits.map(\.place)).compactMap(store.place)
        let byType = Dictionary(grouping: visited, by: \.siteType)
        if !byType.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHead(
                    "Kinds of place",
                    detail: "\(byType.count) of \(SiteType.allCases.count)"
                )
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(SiteType.allCases.filter { byType[$0] != nil }) { type in
                        HStack(spacing: 10) {
                            SitePin(type: type, status: .visited)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("\(byType[type]?.count ?? 0)")
                                    .font(UnigridStyle.figureSmall)
                                    .monospacedDigit()
                                    .foregroundStyle(style.ink)
                                Text(type.name.uppercased())
                                    .font(UnigridStyle.dataLabel)
                                    .foregroundStyle(style.inkSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Visits in each month, January first.
struct VisitsByMonthSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let visits: [Visit]

    var body: some View {
        let counts = StatsReport.visitsByMonth(visits.map(\.summary))
        let months = Calendar.current.shortMonthSymbols
        let points = counts.enumerated().map { (month: months[$0.offset], visits: $0.element) }
        return VStack(alignment: .leading, spacing: 12) {
            SectionHead("Visits by month")
            Chart(points, id: \.month) { point in
                BarMark(
                    x: .value("Month", point.month),
                    y: .value("Visits", point.visits),
                    width: .ratio(0.7)
                )
                .foregroundStyle(style.ink)
            }
            .chartXScale(domain: months)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Visits by month")
            .accessibilityValue(
                points.filter { $0.visits > 0 }.map { "\($0.month): \($0.visits)" }
                    .joined(separator: ", ")
            )
        }
    }
}

/// The weather family (§11), from the snapshot stored with each visit.
struct WeatherStatsSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let visits: [Visit]

    var body: some View {
        let stats = WeatherStats(visits.compactMap { visit in
            visit.weather.map {
                VisitWeather(
                    placeID: visit.place,
                    date: visit.date,
                    highCelsius: $0.highCelsius,
                    lowCelsius: $0.lowCelsius,
                    precipitationMillimetres: $0.precipitationMillimetres,
                    condition: $0.condition
                )
            }
        })
        if stats.measured > 0 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHead("Weather and season", detail: "\(stats.measured) visits measured")
                if let verdict = stats.verdict {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verdict.name)
                            .font(UnigridStyle.figureSmall)
                            .foregroundStyle(style.ink)
                        Text(verdict.detail)
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    if let hottest = stats.hottest, let high = hottest.highCelsius {
                        FigureBlock(
                            value: UnigridsFormat.temperature(celsius: high),
                            label: "Hottest · \(placeName(hottest.placeID))"
                        )
                    }
                    if let coldest = stats.coldest, let low = coldest.lowCelsius {
                        FigureBlock(
                            value: UnigridsFormat.temperature(celsius: low),
                            label: "Coldest · \(placeName(coldest.placeID))"
                        )
                    }
                    if let wettest = stats.wettest, let rain = wettest.precipitationMillimetres {
                        FigureBlock(
                            value: Measurement(value: rain, unit: UnitLength.millimeters)
                                .formatted(.measurement(width: .abbreviated, usage: .rainfall)),
                            label: "Wettest · \(placeName(wettest.placeID))"
                        )
                    }
                    FigureBlock(value: "\(stats.snowVisits)", label: "Snow days")
                    FigureBlock(value: "\(stats.wetVisits)", label: "Wet days")
                }
                Text("Weather from Open-Meteo, CC BY 4.0, fetched once for each visit and kept.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }

    private func placeName(_ id: UnigridsID) -> String {
        store.place(id)?.name ?? "unknown place"
    }
}
