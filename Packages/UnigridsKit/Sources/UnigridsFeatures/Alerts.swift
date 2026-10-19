import Foundation
import SwiftUI
import UnigridsCore
import UnigridsDesign

/// One live NPS alert (SPECIFICATION.md §10, "Live park alerts").
struct ParkAlert: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: String
    let url: String?

    var kind: Kind {
        switch category.lowercased() {
        case "danger": .danger
        case "park closure": .closure
        case "caution": .caution
        default: .information
        }
    }

    enum Kind: Int, Comparable {
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
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
           as? [String: Any],
           let key = plist["NPSAPIKey"] as? String,
           !key.isEmpty
        {
            return key
        }
        return nil
    }

    static var isConfigured: Bool {
        apiKey != nil
    }

    private struct Response: Decodable {
        let data: [ParkAlert]
    }

    static func fetch(parkCode: String) async throws -> [ParkAlert] {
        guard let key = apiKey,
              var components = URLComponents(string: "https://developer.nps.gov/api/v1/alerts")
        else { return [] }
        components.queryItems = [
            URLQueryItem(name: "parkCode", value: parkCode.lowercased()),
            URLQueryItem(name: "limit", value: "20"),
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 15)
        // The key goes in a header, so it never sits in a URL that might be logged.
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data).data
            .sorted { ($0.kind, $0.title) < ($1.kind, $1.title) }
    }
}

/// The guide's Alerts panel: what the park has posted right now.
struct AlertsPanel: View {
    @Environment(\.unigrid) private var style
    let parkCode: String

    private enum Load {
        case loading
        case loaded([ParkAlert])
        case failed
    }

    @State private var load = Load.loading

    var body: some View {
        UnigridPanel(title: GuidePanel.alerts.title) {
            VStack(alignment: .leading, spacing: 12) {
                switch load {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .failed:
                    Text("The NPS could not be reached. Alerts need a connection.")
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.inkSecondary)
                case let .loaded(alerts) where alerts.isEmpty:
                    Text("No alerts posted right now.")
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.inkSecondary)
                case let .loaded(alerts):
                    ForEach(alerts) { alert in
                        AlertRow(alert: alert)
                        if alert.id != alerts.last?.id {
                            Hairline()
                        }
                    }
                }
                Text("Live from the National Park Service")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .task(id: parkCode) {
            do {
                load = try await .loaded(NPSAlerts.fetch(parkCode: parkCode))
            } catch {
                load = .failed
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
            Text(alert.description)
                .font(UnigridStyle.prose)
                .foregroundStyle(style.inkSecondary)
                .lineLimit(expanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .onTapGesture { expanded.toggle() }
            if let link = alert.url.flatMap(URL.init(string:)), !(alert.url ?? "").isEmpty {
                Link("More on nps.gov", destination: link)
                    .font(UnigridStyle.caption)
            }
        }
        .accessibilityElement(children: .combine)
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
