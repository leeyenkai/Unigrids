import Charts
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// What the bundle knows about visiting a place beyond its guide: how busy each month is,
// and the NPS's own fees, hours, directions and contact for a site without a full guide
// (SPECIFICATION.md §6, §10).

/// Recreation visits by month as bars, the busiest month marked, with the years they
/// average and their source.
struct VisitationChart: View {
    @Environment(\.unigrid) private var style
    let visitation: MonthlyVisitation

    private var symbols: [String] {
        Calendar.unigrids.shortMonthSymbols
    }

    private struct Month: Identifiable {
        let number: Int
        let visits: Int

        var id: Int {
            number
        }
    }

    private var months: [Month] {
        visitation.monthly.enumerated().map { Month(number: $0.offset + 1, visits: $0.element) }
    }

    var body: some View {
        if visitation.monthly.count == 12 {
            VStack(alignment: .leading, spacing: 8) {
                GuideFieldLabel("Visitors by month, \(visitation.yearsDescription) average")
                Chart(months) { month in
                    BarMark(
                        x: .value("Month", symbols[month.number - 1]),
                        y: .value("Visits", month.visits),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(
                        month.number == visitation.busiestMonth ? style.ink : style.inkSecondary
                            .opacity(0.5)
                    )
                }
                .chartXScale(domain: symbols)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().font(UnigridStyle.dataLabel)
                    }
                }
                .frame(height: 80)
                Text(summary + " Recreation visits counted by the National Park Service, CC0.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Visitors by month, \(visitation.yearsDescription) average")
            .accessibilityValue(summary)
        }
    }

    private var summary: String {
        let names = Calendar.unigrids.monthSymbols
        guard let busiest = visitation.busiestMonth, let quietest = visitation.quietestMonth
        else { return "" }
        return "Busiest in \(names[busiest - 1]), quietest in \(names[quietest - 1])."
    }
}

/// A leaflet's "When it's busy" panel, for an NPS site with visit counts.
struct VisitationPanel: View {
    let visitation: MonthlyVisitation

    var body: some View {
        UnigridPanel(title: "When it's busy") {
            VisitationChart(visitation: visitation)
        }
    }
}

/// The NPS's own visitor information for a site without a full guide: hours, fees and
/// reservations, then how to get there and whom to ask.
struct VisitorInfoPanels: View {
    @Environment(\.unigrid) private var style
    let info: PlaceVisitorInfo

    /// "(435) 772-3256" as a number to dial.
    private static func dial(_ phone: String) -> URL? {
        URL(string: "tel:" + phone.filter { $0.isNumber || $0 == "+" })
    }

    var body: some View {
        if info.operatingHours != nil || !info.fees.isEmpty || info.reservations != nil {
            PlanYourVisitPanel(
                plan: PlanYourVisit(reservations: info.reservations),
                fees: info.fees,
                hours: info.operatingHours
            )
        }
        if let directions = info.directions, !directions.isEmpty {
            NotePanel(panel: .gettingThere, text: directions, source: "National Park Service")
        }
        if info.phone != nil || info.email != nil {
            UnigridPanel(title: "Contact") {
                VStack(alignment: .leading, spacing: 8) {
                    if let phone = info.phone, let url = Self.dial(phone) {
                        Link(destination: url) { UnigridDataRow(label: "Phone", value: phone) }
                    }
                    if let email = info.email, let url = URL(string: "mailto:" + email) {
                        Link(destination: url) { UnigridDataRow(label: "Email", value: email) }
                    }
                    Text("As the National Park Service lists them.")
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
            }
        }
    }
}
