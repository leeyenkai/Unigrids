import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// What a tap on the map opens: a place's photograph, name, overview, figures and actions
/// (SPECIFICATION.md §5, "bottom card"). An inspector column on iPad and Mac, a sheet that
/// leaves the map usable on iPhone.
struct PlaceOverviewPanel: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var alerts: AlertsCenter?
    @Query private var visits: [Visit]

    let place: Place
    let onOpen: (Place) -> Void
    let onClose: () -> Void

    @State private var showCheckIn = false
    @State private var showStamp = false
    @State private var showAddToTrip = false
    @State private var showExplorer = false

    /// Dangers and closures: what the pin's badge stands for.
    private var urgentCount: Int {
        place.npsParkCode.map { code in
            alerts?.alerts(for: code).count { $0.kind <= .closure } ?? 0
        } ?? 0
    }

    private var placeVisits: [Visit] {
        visits.filter { $0.place == place.id }.sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OverviewBand(place: place, onClose: onClose)
                if let image = place.image {
                    PlacePhoto(image: image, aspectRatio: 16 / 10, maxPoints: 520)
                    PhotoCredit(image: image)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                VStack(alignment: .leading, spacing: 18) {
                    VisitStatusLine(visits: placeVisits)
                    // The map badges a park with a posted closure or danger; this is where
                    // the badge leads.
                    if let code = place.npsParkCode, urgentCount > 0 {
                        CardAlerts(parkCode: code)
                    }
                    if place.summary != nil {
                        OverviewSummary(place: place)
                    } else {
                        Text(place.factualDescription)
                            .font(UnigridStyle.proseSmall)
                            .foregroundStyle(style.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OverviewFigures(place: place)
                    OverviewActions(
                        place: place,
                        hasGuide: place.tier.hasGuide && store.guide(for: place.id) != nil,
                        onOpen: { onOpen(place) },
                        onCheckIn: { showCheckIn = true },
                        onStamp: { showStamp = true },
                        onAddToTrip: { showAddToTrip = true },
                        onExplore: { showExplorer = true }
                    )
                }
                .padding(16)
            }
        }
        .background(style.page)
        .unigridsSheet(isPresented: $showCheckIn) { CheckInSheet(place: place) }
        .unigridsSheet(isPresented: $showStamp) { StampSheet(place: place) }
        .unigridsSheet(isPresented: $showAddToTrip) { AddToTripSheet(place: place) }
        .explorer(isPresented: $showExplorer, place: place)
    }
}

/// The panel's band: the place's name reversed out, with its designation and states.
struct OverviewBand: View {
    let place: Place
    let onClose: () -> Void

    var body: some View {
        BandHeader(place.name, kicker: "\(place.designation) · \(place.statesDescription)") {
            BandCloseButton(action: onClose)
        }
        .accessibilityElement(children: .contain)
    }
}

/// "Visited twice, last in June 2024", or that it is not yet.
struct VisitStatusLine: View {
    @Environment(\.unigrid) private var style
    let visits: [Visit]

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(visits.isEmpty ? Color.clear : style.accent)
                .overlay { Rectangle().strokeBorder(style.accent, lineWidth: 1.5) }
                .frame(width: 10, height: 10)
            Text(text)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(visits.isEmpty ? style.inkSecondary : style.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var text: String {
        guard let latest = visits.first else { return "Not visited yet" }
        let when = latest.date.formatted(UnigridsFormat.month())
        switch visits.count {
        case 1: return "Visited in \(when)"
        case 2: return "Visited twice, last in \(when)"
        default: return "Visited \(visits.count) times, last in \(when)"
        }
    }
}

struct OverviewSummary: View {
    @Environment(\.unigrid) private var style
    let place: Place

    var body: some View {
        if let text = place.summary {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                // A Wikipedia lead is CC BY-SA: credited by article, linked, and marked as
                // shortened.
                if let credit = place.summaryCredit {
                    if let url = place.summaryURL {
                        Link(destination: url) {
                            Text(credit).underline()
                        }
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                    } else {
                        Text(credit)
                            .font(UnigridStyle.caption)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
    }
}

/// The figures a place has, and none it does not.
struct OverviewFigures: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let place: Place

    /// A landmark or a byway is designated, not established.
    private var yearLabel: String {
        switch place.kind {
        case .naturalLandmark, .scenicByway: "Designated"
        default: "Established"
        }
    }

    var body: some View {
        let facts = place.facts
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: 14, alignment: .top)],
                alignment: .leading,
                spacing: 14
            ) {
                if let year = facts.establishedYear {
                    FigureBlock(value: String(year), label: yearLabel, compact: true)
                }
                if let acres = facts.areaAcres {
                    FigureBlock(
                        value: UnigridsFormat.area(acres: acres),
                        label: place.kind == .nationalForest ? "Within boundary" : "Area",
                        compact: true
                    )
                }
                if let route = store.route(for: place.id) {
                    FigureBlock(
                        value: UnigridsFormat.distance(metres: route.length),
                        label: "Route, mapped",
                        compact: true
                    )
                }
                if let annual = facts.annualVisits {
                    FigureBlock(
                        value: UnigridsFormat.visitors(annual),
                        label: facts.annualVisitsYear.map { "Visits, \($0)" } ?? "Visits",
                        compact: true
                    )
                }
            }
            if let fee = facts.entranceFee {
                UnigridDataRow(label: "Entrance", value: fee)
            }
        }
    }
}

/// The card's actions (SPECIFICATION.md §5): open the guide, check in, stamp, add to a
/// trip, directions, and the official page.
struct OverviewActions: View {
    @Environment(\.leafletMode) private var leafletMode
    let place: Place
    let hasGuide: Bool
    let onOpen: () -> Void
    let onCheckIn: () -> Void
    let onStamp: () -> Void
    let onAddToTrip: () -> Void
    var onExplore: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            if !leafletMode {
                Button(action: onOpen) {
                    Label(hasGuide ? "Open guide" : "Open page", symbol: .openGuide)
                }
                .buttonStyle(BrochureButtonStyle(.primary))
            }

            if let onExplore {
                Button(action: onExplore) {
                    Label("Explore in 3D", symbol: .explore3D)
                }
                .buttonStyle(BrochureButtonStyle(leafletMode ? .primary : .secondary))
            }

            TwoUpRow {
                Button(action: onCheckIn) {
                    Label("Check in", symbol: .checkIn)
                }
                Button(action: onStamp) {
                    Label { Text("Stamp") } icon: { StampIcon() }
                }
            }
            .buttonStyle(BrochureButtonStyle(.secondary))

            TwoUpRow {
                Button(action: onAddToTrip) {
                    Label("Add to trip", symbol: .addToTrip)
                }
                Button {
                    openInMaps(place)
                } label: {
                    Label("Directions", symbol: .directions)
                }
            }
            .buttonStyle(BrochureButtonStyle(.secondary))

            if let url = place.officialURL ?? place.infoURL {
                Link(destination: url) {
                    Label("Website", symbol: .website)
                }
                .buttonStyle(BrochureButtonStyle(.secondary))
            } else if let url = lookUpURL {
                // No official page Unigrids can vouch for: offer a search, which sends the
                // place's name to Wikipedia only when the reader asks.
                Link(destination: url) {
                    Label("Look it up on Wikipedia", symbol: .search)
                }
                .buttonStyle(BrochureButtonStyle(.secondary))
            }
        }
    }
}

extension OverviewActions {
    private var lookUpURL: URL? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/index.php")
        components?.queryItems = [
            URLQueryItem(name: "search", value: "\(place.name) \(place.designation)"),
        ]
        return components?.url
    }
}

/// Hand the place to Apple Maps for directions. Unigrids does no routing of its own.
@MainActor
func openInMaps(_ place: Place) {
    let location = CLLocation(latitude: place.centre.latitude, longitude: place.centre.longitude)
    let item = MKMapItem(
        location: location,
        address: MKAddress(fullAddress: place.statesDescription, shortAddress: place.name)
    )
    item.name = "\(place.name) \(place.designation)"
    item.openInMaps()
}
