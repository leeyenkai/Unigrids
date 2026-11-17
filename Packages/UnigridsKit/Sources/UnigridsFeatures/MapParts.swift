import MapKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// The map screen's smaller parts: the region shortcuts, search suggestions, and the line
// that says what is filtered or still loading.

// MARK: - Region shortcuts

/// Alaska, Hawaii and the territories are one tap away (SPECIFICATION.md §5), and so are
/// Japan, Norway and their outlying islands once their places ship (`MapRegions`).
struct RegionShortcutBar: View {
    @Environment(\.unigrid) private var style
    /// The countries with places in the data, in order.
    var countries: [Country] = [.unitedStates]
    /// The country on screen. Its own regions follow its name; the others show only
    /// their name, so Svalbard is a tap away from Norway without a long scroll past
    /// the US territories.
    var inView: Country?
    let onSelect: (BoundingBox) -> Void

    /// One country: its shortcuts, as before there were others. Several: the world,
    /// then each country by name, the one in view followed by its regions.
    private var regions: [(String, BoundingBox)] {
        guard countries.count > 1 else {
            return countries.flatMap { country in
                MapRegions.shortcuts(in: country).map { ($0.name, $0.box) }
            }
        }
        return [("World", MapRegions.world)] + countries.flatMap { country in
            let name = [(country.name, MapRegions.home(country))]
            guard country == inView else { return name }
            // The first shortcut is the country's home view, which its name already frames.
            return name + MapRegions.shortcuts(in: country).dropFirst().map { ($0.name, $0.box) }
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(regions, id: \.0) { name, box in
                    Button {
                        onSelect(box)
                    } label: {
                        Text(name.uppercased())
                            .font(UnigridStyle.dataLabel)
                            .tracking(1.1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(style.bandInk)
                    Rectangle()
                        .fill(style.bandInkSecondary.opacity(0.4))
                        .frame(width: 1, height: 12)
                }
            }
            .padding(.horizontal, 6)
        }
        .scrollIndicators(.hidden)
        .background(style.band)
    }
}

// The key, filters and layers live in MapKey.swift.

// MARK: - Search

enum MapSearchResult {
    case place(Place)
    case pointOfInterest(PointOfInterest)
}

/// Search covers parks, sights and visitor centres (SPECIFICATION.md §5).
struct MapSearchSuggestions: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let query: String
    let onSelect: (MapSearchResult) -> Void

    private var isWorld: Bool {
        store.nationalParks.contains { $0.country != .unitedStates }
    }

    var body: some View {
        let places = store.search(query, limit: 8)
        let sights = store.searchPointsOfInterest(query, limit: 6)
        let searched = query.trimmingCharacters(in: .whitespaces).count >= 2
        if searched, places.isEmpty, sights.isEmpty {
            Text(
                "Nothing matches \u{201C}\(query)\u{201D}. Try a park, forest or refuge "
                    + "by name, or " + (isWorld ? "a state, prefecture or county." : "a state.")
            )
            .font(UnigridStyle.rowDetail)
            .foregroundStyle(style.inkSecondary)
        }
        ForEach(places) { place in
            Button {
                onSelect(.place(place))
            } label: {
                HStack(spacing: 10) {
                    SitePin(place: place)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(place.name)
                            .font(UnigridStyle.rowTitle)
                        Text("\(place.designation) · \(place.bandLine)")
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
        ForEach(sights) { poi in
            Button {
                onSelect(.pointOfInterest(poi))
            } label: {
                HStack(spacing: 10) {
                    Image(poi.kind == .visitorCentre ? UnigridsSymbol.visitorCentre : .sight)
                        .foregroundStyle(style.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(poi.name)
                            .typeset(for: poi.name)
                            .font(UnigridStyle.rowTitle)
                        Text("\(poi.kind.name) · \(store.place(poi.placeID)?.name ?? "")")
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
    }
}

/// Why "Where am I" found nothing.
enum LocationProblem: Identifiable {
    case refused
    case unavailable

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .refused: "Location is off for Unigrids"
        case .unavailable: "No position just now"
        }
    }

    var message: String {
        switch self {
        case .refused:
            "To centre the map on you, allow location in Settings. Unigrids uses it on the "
                + "device and never stores it."
        case .unavailable:
            "Your device could not find its position. Try again with a clearer view of the sky."
        }
    }

    var settingsURL: URL? {
        guard self == .refused else { return nil }
        #if os(iOS)
            return URL(string: "app-settings:")
        #else
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security"
                    + "?Privacy_LocationServices"
            )
        #endif
    }
}

/// What is narrowing or still loading on the map, said in a line under the shortcuts:
/// "Filtered · 212 of 5,524 · Clear", "Loading roads and rail…".
struct MapStatusChips: View {
    @Environment(\.unigrid) private var style
    @Environment(TransportStore.self) private var transport: TransportStore?
    let filter: MapFilter
    let shown: Int
    let total: Int
    let layersWanted: Bool
    let onClear: () -> Void
    let onRetryLayers: () -> Void

    private var layersPending: Bool {
        layersWanted && (transport?.isLoading == true || transport?.failed == true)
    }

    var body: some View {
        if filter.isNarrowed || layersPending {
            WrappingRow(spacing: 6) {
                if filter.isNarrowed {
                    Button(action: onClear) {
                        HStack(spacing: 6) {
                            Text("Filtered · \(shown.formatted()) of \(total.formatted())")
                            Text("Clear").fontWeight(.bold)
                        }
                    }
                    .accessibilityLabel(
                        "Filtered, \(shown) of \(total) places shown. Clear the filter."
                    )
                }
                if layersWanted, transport?.isLoading == true {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Loading roads and rail…")
                    }
                } else if layersWanted, transport?.failed == true {
                    Button(action: onRetryLayers) {
                        HStack(spacing: 6) {
                            Text("Roads and rail did not load")
                            Text("Retry").fontWeight(.bold)
                        }
                    }
                }
            }
            .font(UnigridStyle.dataLabel)
            .textCase(.uppercase)
            .buttonStyle(.plain)
            .foregroundStyle(style.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.page.opacity(0.94))
        }
    }
}
