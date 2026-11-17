import Foundation
import UnigridsCore

/// The NSW National Parks and Wildlife Service's alerts, one RSS item a park, each holding
/// that park's notices under headings: "Closed parks", "Closed areas", "Fire bans",
/// "Safety alerts", "Other planned events".
enum NPWSAlerts {
    struct Item: Hashable, Sendable {
        let park: String
        let link: String
        let notices: [Notice]
    }

    struct Notice: Hashable, Sendable {
        let heading: String
        let title: String
        let body: String
    }

    static let url = URL(string: "https://www.nationalparks.nsw.gov.au/api/rssfeed/get?type=alerts")

    static func fetch() async throws -> [Item] {
        guard let url else { throw URLError(.badURL) }
        return try await items(from: AbroadFetch.data(url))
    }

    static func items(from data: Data) -> [Item] {
        let reader = RSSReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.items.map { item in
            Item(park: item.title, link: item.link, notices: notices(in: item.description))
        }
    }

    /// The headings that start a notice; any other bold line is part of the one before.
    static let headings = [
        "Closed parks", "Closed areas", "Fire bans", "Safety alerts", "Other incidents",
        "Other planned events", "Fires",
    ]

    static func notices(in html: String) -> [Notice] {
        let pattern = #"<strong>\s*([^<:]+?)\s*:\s*([^<]*)</strong>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: text.length))
            .filter { match in
                let heading = text.substring(with: match.range(at: 1))
                return headings.contains { heading.hasPrefix($0) }
            }
        return matches.enumerated().map { index, match in
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : text
                .length
            let body = text.substring(with: NSRange(
                location: bodyStart,
                length: bodyEnd - bodyStart
            ))
            return Notice(
                heading: text.substring(with: match.range(at: 1)),
                title: AustralianFires.plainText(text.substring(with: match.range(at: 2))),
                body: AustralianFires.plainText(body)
            )
        }
    }

    /// A closed park or area is a closure, a fire ban or safety alert a caution, anything
    /// else a notice.
    static func alert(for notice: Notice, of item: Item) -> ParkAlert {
        let category = switch notice.heading {
        case let heading where heading.hasPrefix("Closed"): "Park Closure"
        case "Fire bans", "Safety alerts": "Caution"
        case let heading where heading.hasPrefix("Fires"): "Caution"
        default: "Information"
        }
        return ParkAlert(
            id: "npws:\(item.park):\(notice.heading):\(notice.title)",
            title: notice.title.isEmpty ? notice.heading : notice.title,
            description: notice.body,
            category: category,
            url: item.link,
            parkCode: nil,
            source: .australianFeeds
        )
    }

    /// The item for a park: its title is the park's full name, "Blue Mountains National
    /// Park", folded so a macron or a case difference does not split them.
    static func item(for place: Place, in items: [Item]) -> Item? {
        let wanted = fold("\(place.name) National Park")
        return items.first { fold($0.park) == wanted }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private final class RSSReader: NSObject, XMLParserDelegate {
        struct Raw {
            var title = "", link = "", description = ""
        }

        var items: [Raw] = []
        private var current: Raw?
        private var element = ""

        func parser(
            _ parser: XMLParser,
            didStartElement name: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            element = name
            if name == "item" {
                current = Raw()
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch element {
            case "title": current?.title += string
            case "link": current?.link += string
            case "description": current?.description += string
            default: break
            }
        }

        func parser(
            _ parser: XMLParser,
            didEndElement name: String,
            namespaceURI: String?,
            qualifiedName: String?
        ) {
            if name == "item", let item = current {
                items.append(Raw(
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    link: item.link.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: item.description
                ))
                current = nil
            }
            element = ""
        }
    }
}

extension AlertsCenter {
    /// Each Australian park's warnings: its state's fire feed, fetched once for every
    /// park it covers, and for a New South Wales park the NPWS's own alerts; each park at
    /// most hourly. A park whose state has no readable feed is not covered.
    func refreshAustralia(_ parks: [(Place, PlaceBoundary?)], force: Bool = false) async {
        let stale = parks.filter { (force || !isFresh($0.0.id)) && Self.covers($0.0) }
        guard !stale.isEmpty else { return }
        let feeds = Set(stale.compactMap { AustralianFires.feed(for: $0.0) })
        var incidents: [AustralianFires.Feed: [FireIncident]] = [:]
        await withTaskGroup(of: (AustralianFires.Feed, [FireIncident]?).self) { group in
            for feed in feeds {
                group.addTask { await (feed, try? AustralianFires.fetch(feed)) }
            }
            for await (feed, answer) in group {
                if let answer {
                    incidents[feed] = answer
                }
            }
        }
        let needsNPWS = stale.contains { AustralianFires.feed(for: $0.0) == .nswRFS }
        let npws: [NPWSAlerts.Item]? = needsNPWS ? try? await NPWSAlerts.fetch() : []
        guard !Task.isCancelled else { return }
        for (place, boundary) in stale {
            guard let feed = AustralianFires.feed(for: place),
                  let fires = incidents[feed]
            else {
                markFailed(place.id)
                continue
            }
            var alerts = fires
                .filter { AustralianFires.touches($0, place: place, boundary: boundary) }
                .map(AustralianFires.alert(for:))
            if feed == .nswRFS, let npws, let item = NPWSAlerts.item(for: place, in: npws) {
                alerts += item.notices.map { NPWSAlerts.alert(for: $0, of: item) }
            }
            record(alerts, for: place.id)
        }
    }
}

extension AustralianFires {
    /// The feed for a park's first state or territory that has one.
    static func feed(for place: Place) -> Feed? {
        place.subdivisions.lazy.compactMap { Feed.covering($0.code) }.first
    }
}
