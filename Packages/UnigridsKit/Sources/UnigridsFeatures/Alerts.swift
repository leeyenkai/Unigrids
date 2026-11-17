import Foundation
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// One live alert (SPECIFICATION.md §10, "Live park alerts"), decoded from the NPS API's
/// shape.
struct ParkAlert: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: String
    let url: String?
    /// The NPS park code the alert is posted for, lower case as the API sends it.
    let parkCode: String?
    /// Who posted it. Not in the NPS's JSON: everything decoded here is the NPS's.
    var source: AlertSource = .nps

    private enum CodingKeys: String, CodingKey {
        case id, title, description, category, url, parkCode
    }

    var kind: Kind {
        switch category.lowercased() {
        case "danger": .danger
        case "park closure": .closure
        case "caution": .caution
        default: .information
        }
    }

    enum Kind: Int, Comparable, Hashable {
        case danger
        case closure
        case caution
        case information

        var name: String {
            switch self {
            case .danger: "Danger"
            case .closure: "Closure"
            case .caution: "Caution"
            case .information: "Information"
            }
        }

        static func < (lhs: Kind, rhs: Kind) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

/// Live alerts, fetched straight from the NPS API.
///
/// There is no proxy: the app calls `developer.nps.gov` itself with a key that ships in
/// the build (SPECIFICATION.md §12). The key is never in the repository — it comes from a
/// gitignored `Secrets.plist` that `scripts/write-secrets.sh` writes from `.env`, so a
/// clone without a key builds an app whose guides simply have no Alerts panel.
enum NPSAlerts {
    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let key = (plist as? [String: Any])?["NPSAPIKey"] as? String,
              !key.isEmpty else { return nil }
        return key
    }

    static var isConfigured: Bool {
        apiKey != nil
    }

    struct Response: Decodable {
        let data: [ParkAlert]
        let total: Int?

        static let empty = Response(data: [], total: 0)

        private enum CodingKeys: String, CodingKey {
            case data
            case total
        }

        init(data: [ParkAlert], total: Int?) {
            self.data = data
            self.total = total
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // Each alert on its own: one posted with a missing field costs that alert, not
            // the page.
            data = try container.decode([Lossy<ParkAlert>].self, forKey: .data)
                .compactMap(\.value)
            // The API sends its counts as strings.
            if let text = try? container.decode(String.self, forKey: .total) {
                total = Int(text)
            } else {
                total = try? container.decode(Int.self, forKey: .total)
            }
        }
    }

    static let pageSize = 500

    /// Every alert posted across the park system, a page of five hundred at a time — a
    /// few requests for the whole country, rather than one per park. Pages continue while
    /// they come back full, whether or not the response says how many there are.
    static func fetchAll() async throws -> [ParkAlert] {
        try await fetch(parkCodes: nil)
    }

    /// The alerts for some parks in one request rather than one each, or for every park.
    static func fetch(parkCodes: [String]?) async throws -> [ParkAlert] {
        var alerts: [ParkAlert] = []
        var start = 0
        while true {
            var parameters = [
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "start", value: String(start)),
            ]
            if let parkCodes {
                guard !parkCodes.isEmpty else { return [] }
                parameters.append(URLQueryItem(
                    name: "parkCode",
                    value: parkCodes.map { $0.lowercased() }.joined(separator: ",")
                ))
            }
            let page = try await request(parameters: parameters)
            alerts += page.data
            start += pageSize
            if !morePages(received: page.data.count, start: start, total: page.total) {
                return alerts
            }
        }
    }

    /// Whether to ask for the next page: the last was full, the total (when sent) is not
    /// yet reached, and the run is within a sane bound.
    static func morePages(received: Int, start: Int, total: Int?) -> Bool {
        guard received == pageSize, start < 10000 else { return false }
        return total.map { start < $0 } ?? true
    }

    private static func request(parameters: [URLQueryItem]) async throws -> Response {
        guard let key = apiKey,
              var components = URLComponents(string: "https://developer.nps.gov/api/v1/alerts")
        else { return Response.empty }
        components.queryItems = parameters
        guard let url = components.url else { return Response.empty }
        var request = URLRequest(url: url, timeoutInterval: 20)
        // The key goes in a header, so it never sits in a URL that might be logged.
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

/// A value that decodes if it can, and is nil if it cannot.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Every park's live alerts, fetched once for the whole system and shared by the map's
/// badges, the guides and leaflets, and the planner's conflict flags (SPECIFICATION.md §5,
/// §10).
///
/// Nothing is kept across launches: alerts are only worth showing while they are fresh,
/// and an hour-old copy is refetched rather than trusted. A failure backs off before the
/// next try — every user shares the key's hourly limit, and an app that asked again on
/// every map visit after a failure would spend it for everyone.
@MainActor
@Observable
public final class AlertsCenter {
    public private(set) var lastUpdated: Date?
    private(set) var byPark: [String: [ParkAlert]] = [:]
    private(set) var lastFailed = false
    private var loading = false
    private var failures = 0
    private var retryAfter: Date?
    /// Warnings abroad, by place, from JMA and Varsom: fetched for a place when its page
    /// opens, and for every Japanese park at once for the map's badges.
    private(set) var abroad: [UnigridsID: [ParkAlert]] = [:]
    private(set) var abroadUpdated: [UnigridsID: Date] = [:]
    private(set) var abroadFailed: Set<UnigridsID> = []
    private var jmaFetched: Date?

    public init() {}

    var isConfigured: Bool {
        NPSAlerts.isConfigured
    }

    /// Fetch unless the last fetch is under an hour old, or a failure is still backing
    /// off. Failure keeps whatever was there: no badge is better than a wrong one, and a
    /// stale one is labelled by its time.
    public func refreshIfStale() async {
        guard NPSAlerts.isConfigured, !loading else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 3600 {
            return
        }
        if let retryAfter, Date() < retryAfter {
            return
        }
        loading = true
        defer { loading = false }
        guard let alerts = try? await NPSAlerts.fetchAll() else {
            failures += 1
            lastFailed = true
            // Two minutes, then four, eight… up to an hour.
            retryAfter = Date().addingTimeInterval(min(3600, 60 * pow(2, Double(failures))))
            return
        }
        failures = 0
        lastFailed = false
        retryAfter = nil
        var grouped: [String: [ParkAlert]] = [:]
        for alert in alerts {
            guard let code = alert.parkCode?.uppercased(), !code.isEmpty else { continue }
            grouped[code, default: []].append(alert)
        }
        byPark = grouped.mapValues { $0.sorted { ($0.kind, $0.title) < ($1.kind, $1.title) } }
        lastUpdated = Date()
    }

    /// Whether this build can show live alerts for a place: an NPS site, in a build that
    /// carries a key. Every screen asks this rather than looking for a park code, so
    /// another country's warning service joins here and nowhere else.
    /// Abroad, every national park: JMA's warnings need no key, nor do Varsom's.
    static func covers(_ place: Place) -> Bool {
        switch place.country {
        case .unitedStates: place.npsParkCode != nil && NPSAlerts.isConfigured
        case .japan, .norway: place.kind == .nationalPark
        }
    }

    /// Who posts a place's alerts.
    static func source(for place: Place) -> AlertSource {
        switch place.country {
        case .unitedStates: .nps
        case .japan: .jma
        case .norway: .varsom
        }
    }

    /// A place's alerts, most urgent first.
    func alerts(for place: Place) -> [ParkAlert] {
        guard place.country == .unitedStates else { return abroad[place.id] ?? [] }
        guard let parkCode = place.npsParkCode else { return [] }
        return byPark[parkCode.uppercased()] ?? []
    }

    /// When a place's alerts were last fetched, if they have been.
    func updated(for place: Place) -> Date? {
        place.country == .unitedStates ? lastUpdated : abroadUpdated[place.id]
    }

    /// Whether the last fetch of a place's alerts failed.
    func failed(for place: Place) -> Bool {
        place.country == .unitedStates ? lastFailed : abroadFailed.contains(place.id)
    }

    /// A place's warnings abroad, unless fetched in the last hour: JMA's for the
    /// volcanoes inside its outline, Varsom's where its centre lies.
    func refreshAbroad(_ place: Place, boundary: PlaceBoundary?) async {
        guard place.country != .unitedStates, Self.covers(place) else { return }
        if let updated = abroadUpdated[place.id], Date().timeIntervalSince(updated) < 3600 {
            return
        }
        switch place.country {
        case .japan:
            await refreshJapan([(place, boundary)])
        case .norway:
            do {
                let alerts = try await VarsomAvalanche.alerts(at: place.centre)
                record(alerts, for: place.id)
            } catch {
                abroadFailed.insert(place.id)
            }
        case .unitedStates:
            break
        }
    }

    /// JMA's warnings for every Japanese park given, from one fetch of the volcano list
    /// and the warnings in force; at most hourly.
    func refreshJapan(_ parks: [(Place, PlaceBoundary?)], force: Bool = false) async {
        guard !parks.isEmpty else { return }
        let fresh = jmaFetched.map { Date().timeIntervalSince($0) < 3600 } ?? false
        if !force, fresh, parks.allSatisfy({ abroadUpdated[$0.0.id] != nil }) {
            return
        }
        guard let (volcanoes, warnings) = try? await JMAVolcanoes.fetch() else {
            for (place, _) in parks {
                abroadFailed.insert(place.id)
            }
            return
        }
        jmaFetched = Date()
        let byCode = Dictionary(grouping: warnings, by: \.volcanoCode)
        for (place, boundary) in parks {
            // A volcano is the park's when its summit lies inside the outline, or, for a
            // park drawn without one, within ten kilometres of its centre.
            let inside = volcanoes.filter { volcano in
                boundary.map { $0.contains(volcano.location) }
                    ?? (volcano.location.distance(to: place.centre) < 10000)
            }
            let alerts = inside.flatMap { volcano in
                (byCode[volcano.code] ?? []).map { JMAVolcanoes.alert(for: $0, volcano: volcano) }
            }
            record(alerts, for: place.id)
        }
    }

    private func record(_ alerts: [ParkAlert], for id: UnigridsID) {
        abroad[id] = alerts.sorted { ($0.kind, $0.title) < ($1.kind, $1.title) }
        abroadUpdated[id] = Date()
        abroadFailed.remove(id)
    }

    /// The badge a place's pin carries, if any: danger outranks closure, and cautions and
    /// notices do not badge at all.
    func mapLevel(for place: Place) -> MapAlertLevel? {
        let kinds = Set(alerts(for: place).map(\.kind))
        if kinds.contains(.danger) {
            return .danger
        }
        if kinds.contains(.closure) {
            return .closure
        }
        return nil
    }
}

/// The guide's Alerts panel: what the park has posted right now, from the shared fetch.
struct AlertsPanel: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    @Environment(AlertsCenter.self) private var center: AlertsCenter?
    let place: Place

    var body: some View {
        UnigridPanel(title: GuidePanel.alerts.title) {
            AlertList(place: place)
        }
        .task(id: place.id) {
            if place.country == .unitedStates {
                await center?.refreshIfStale()
            } else {
                await center?.refreshAbroad(place, boundary: store.boundary(for: place.id))
            }
        }
    }
}

/// A park's alerts as a list, with when they were fetched: for the guide's panel, a
/// leaflet and the map's overview card.
struct AlertList: View {
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var center: AlertsCenter?
    let place: Place

    private var source: AlertSource {
        AlertsCenter.source(for: place)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let center, let updated = center.updated(for: place) {
                let alerts = center.alerts(for: place)
                if alerts.isEmpty {
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
                Text("Live from \(source.name) · updated "
                    + updated.formatted(date: .omitted, time: .shortened))
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
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
