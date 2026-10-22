import Charts
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The guide's weather and seasons panel: the week ahead, the year at a glance as monthly
/// highs, lows and precipitation, and the NPS's own note on what each season is like
/// (SPECIFICATION.md §6, §10).
struct WeatherPanel: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let place: Place
    let note: String?

    @State private var forecasts = Forecasts()

    var body: some View {
        UnigridPanel(title: GuidePanel.weather.title) {
            VStack(alignment: .leading, spacing: 16) {
                WeekAhead(days: weekAhead)
                if let climate = store.climate(for: place.id) {
                    ClimateChart(climate: climate)
                }
                if let note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        GuideFieldLabel("From the National Park Service")
                        Text(note)
                            .font(UnigridStyle.prose)
                            .foregroundStyle(style.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Forecast and climate from Open-Meteo, CC BY 4.0.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .task(id: place.id) { await forecasts.load([place]) }
    }

    private var weekAhead: [DailyWeather] {
        guard let daily = forecasts.byPlace[place.id] else { return [] }
        return Array(daily.days.prefix(7))
    }
}

/// Seven days, a column each: the day, an icon, the high over the low.
private struct WeekAhead: View {
    @Environment(\.unigrid) private var style
    let days: [DailyWeather]

    var body: some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                GuideFieldLabel("The week ahead, at the park's centre")
                HStack(spacing: 0) {
                    ForEach(days, id: \.date) { day in
                        VStack(spacing: 5) {
                            Text(weekday(day.date))
                                .font(UnigridStyle.dataLabel)
                                .foregroundStyle(style.inkSecondary)
                            Image(systemName: day.condition.map(WeatherSymbol.name) ?? "cloud")
                                .symbolRenderingMode(.multicolor)
                                .font(.body)
                                .frame(height: 22)
                            if let high = day.highCelsius {
                                Text(UnigridsFormat.temperature(celsius: high))
                                    .font(UnigridStyle.dataValue)
                                    .foregroundStyle(style.ink)
                            }
                            if let low = day.lowCelsius {
                                Text(UnigridsFormat.temperature(celsius: low))
                                    .font(UnigridStyle.caption)
                                    .foregroundStyle(style.inkSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private func weekday(_ key: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: key) else { return key }
        return date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }
}

/// The year at a glance: each month's mean high and low as a bar between them, and its
/// precipitation beneath.
struct ClimateChart: View {
    @Environment(\.unigrid) private var style
    let climate: MonthlyClimate

    private var symbols: [String] {
        Calendar.current.shortMonthSymbols
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GuideFieldLabel("The year at a glance, \(climate.period) average")
            Chart(climate.months) { month in
                BarMark(
                    x: .value("Month", symbols[month.month - 1]),
                    yStart: .value("Low", display(month.lowCelsius)),
                    yEnd: .value("High", display(month.highCelsius)),
                    width: .ratio(0.55)
                )
                .foregroundStyle(style.accent)
            }
            .chartXScale(domain: symbols)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(style.rule)
                    AxisValueLabel {
                        if let degrees = value.as(Double.self) {
                            Text("\(Int(degrees))°").font(UnigridStyle.dataLabel)
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 140)
            Chart(climate.months) { month in
                BarMark(
                    x: .value("Month", symbols[month.month - 1]),
                    y: .value("Precipitation", month.precipitationMillimetres),
                    width: .ratio(0.55)
                )
                .foregroundStyle(style.inkSecondary.opacity(0.6))
            }
            .chartXScale(domain: symbols)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(UnigridStyle.dataLabel)
                }
            }
            .frame(height: 52)
            Text(summary)
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly climate, \(climate.period) average")
        .accessibilityValue(summary)
    }

    /// Degrees in the reader's own scale, for the axis.
    private func display(_ celsius: Double) -> Double {
        UnigridsFormat.usesUSUnits(.current) ? celsius * 9 / 5 + 32 : celsius
    }

    private var summary: String {
        var parts: [String] = []
        if let warmest = climate.warmest {
            parts.append("Warmest in \(Calendar.current.monthSymbols[warmest.month - 1]), "
                + "highs near \(UnigridsFormat.temperature(celsius: warmest.highCelsius))")
        }
        if let coldest = climate.coldest {
            parts.append("coldest in \(Calendar.current.monthSymbols[coldest.month - 1]), "
                + "lows near \(UnigridsFormat.temperature(celsius: coldest.lowCelsius))")
        }
        if let wettest = climate.wettest {
            parts.append("wettest in \(Calendar.current.monthSymbols[wettest.month - 1])")
        }
        return parts.joined(separator: "; ") + ". Bars show the mean daily high and low; "
            + "precipitation below. One point stands for the whole park, so higher ground "
            + "runs colder."
    }
}
