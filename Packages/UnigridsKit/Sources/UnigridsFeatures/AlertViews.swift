import SwiftUI
import UnigridsCore
import UnigridsDesign

/// A park's alerts as a list, with when they were fetched: for the guide's panel, a
/// leaflet and the map's overview card.
struct AlertList: View {
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var center: AlertsCenter?
    let place: Place

    /// The time alone for today's fetch; the date too for an older one, so a list left
    /// open offline for days does not pass for this afternoon's.
    static func when(_ updated: Date) -> String {
        Calendar.current.isDateInToday(updated)
            ? updated.formatted(date: .omitted, time: .shortened)
            : updated.formatted(UnigridsFormat.moment(in: .current))
    }

    private var source: AlertSource {
        AlertsCenter.source(for: place)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let center, let updated = center.updated(for: place) {
                let alerts = center.alerts(for: place)
                if alerts.isEmpty, source == .jma, center.volcanoCount[place.id] == 0 {
                    Text("None of the volcanoes JMA monitors lies in this park, so it has no "
                        + "eruption warnings to give.")
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.inkSecondary)
                } else if alerts.isEmpty {
                    Text(source.noneText)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.inkSecondary)
                } else {
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert)
                        if alert.id != alerts.last?.id {
                            Hairline()
                        }
                    }
                }
                Text("Live from \(source.name) · updated " + Self.when(updated))
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                if center.failed(for: place) {
                    Text("The last refresh failed, so these may be out of date.")
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
            } else if center?.failed(for: place) == true {
                Text(source.unreachable)
                    .font(UnigridStyle.prose)
                    .foregroundStyle(style.inkSecondary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A card's short version: the dangers and closures by title — what the pin's badge stands
/// for — and how many cautions and notices the full list holds.
struct CardAlerts: View {
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var center: AlertsCenter?
    let place: Place

    var body: some View {
        let all = center?.alerts(for: place) ?? []
        let urgent = all.filter { $0.kind <= .closure }
        VStack(alignment: .leading, spacing: 8) {
            SectionHead("Alerts", detail: "\(urgent.count)")
            ForEach(urgent.prefix(3)) { alert in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Kicker(alert.kind.name)
                    Text(alert.title)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            let more = all.count - min(urgent.count, 3)
            if more > 0 {
                Text("\(more) more on its page.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}

struct AlertRow: View {
    @Environment(\.unigrid) private var style
    let alert: ParkAlert
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(ink)
                    .frame(width: 9, height: 9)
                Kicker(alert.kind.name)
            }
            Text(alert.title)
                .font(UnigridStyle.itemTitle)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                expanded.toggle()
            } label: {
                Text(alert.description)
                    .font(UnigridStyle.prose)
                    .foregroundStyle(style.inkSecondary)
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Shows less" : "Shows the whole alert")
            if let link = alert.url.flatMap(URL.init(string:)), !(alert.url ?? "").isEmpty {
                Link(alert.source.linkLabel, destination: link)
                    .font(UnigridStyle.caption)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var ink: Color {
        switch alert.kind {
        case .danger: style.seal
        case .closure: style.ink
        case .caution: style.trail
        case .information: style.inkSecondary
        }
    }
}
