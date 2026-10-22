import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Add stops to a trip, several at a time: any place, anything inside the trip's parks —
/// a sight, a visitor centre, a campground, a trail — or somewhere to sleep or stop on the
/// way, found by name.
struct StopPicker: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    let trip: Trip

    enum Scope: String, CaseIterable, Identifiable {
        case places = "Places"
        case inside = "In these parks"
        case anywhere = "Lodging and more"

        var id: String {
            rawValue
        }
    }

    @State private var scope = Scope.places
    @State private var query = ""
    @State private var added: Int = 0
    @State private var error: String?

    var body: some View {
        SheetPage(
            "Add stops",
            kicker: trip.name,
            actions: .done { dismiss() },
            height: 680
        ) {
            VStack(spacing: 0) {
                Picker("Kind of stop", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, UnigridStyle.pageMargin)
                .padding(.vertical, 10)
                switch scope {
                case .places:
                    PlaceStopList(trip: trip, query: query, onAdd: add)
                case .inside:
                    InsideStopList(trip: trip, query: query, onAdd: add)
                case .anywhere:
                    SearchedStopList(trip: trip, query: query, onAdd: add)
                }
                if added > 0 || error != nil {
                    Group {
                        if let error {
                            ErrorLine(error)
                        } else {
                            Text("\(added) added to the trip")
                                .font(UnigridStyle.rowDetail)
                                .foregroundStyle(style.ink)
                        }
                    }
                    .padding(UnigridStyle.pageMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.page)
                }
            }
            .searchable(text: $query, prompt: prompt)
        }
    }

    private var prompt: String {
        switch scope {
        case .places: "Parks, monuments, forests, state parks"
        case .inside: "Sights, visitor centres, trails"
        case .anywhere: "A lodge, a town, a viewpoint"
        }
    }

    private func add(_ placeID: UnigridsID, _ target: StopTarget) {
        do {
            try LogStore(context: context).addStop(placeID, to: trip, target: target)
            added += 1
            error = nil
        } catch {
            self.error = "That stop could not be added: \(error.localizedDescription)"
        }
    }
}

/// Every place, searched; the national parks first when nothing is typed.
private struct PlaceStopList: View {
    @Environment(\.referenceStore) private var store
    let trip: Trip
    let query: String
    let onAdd: (UnigridsID, StopTarget) -> Void

    private var results: [Place] {
        query.isEmpty ? store.nationalParks : store.search(query, limit: 80)
    }

    var body: some View {
        List {
            if results.isEmpty {
                NoResults(query: query)
            }
            ForEach(results) { place in
                let onTrip = trip.orderedStops
                    .contains { $0.place == place.id && $0.target == .place }
                AddStopRow(isAdded: onTrip, action: { onAdd(place.id, .place) }) {
                    PlaceRow(place: place, status: .none)
                }
            }
        }
        .listStyle(.plain)
    }
}

/// What is inside the trip's parks: their sights, visitor centres and campgrounds, and
/// their trails.
private struct InsideStopList: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let trip: Trip
    let query: String
    let onAdd: (UnigridsID, StopTarget) -> Void

    private var places: [Place] {
        var seen: Set<UnigridsID> = []
        return trip.orderedStops.compactMap { store.place($0.place) }
            .filter { seen.insert($0.id).inserted }
    }

    private func matches(_ name: String) -> Bool {
        query.isEmpty || name.localizedStandardContains(query)
    }

    var body: some View {
        List {
            if places.isEmpty {
                Text("Add a park first; its sights, trails and campgrounds are listed here.")
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.inkSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(places) { place in
                let pois = store.pointsOfInterest(in: place.id)
                    .filter { $0.kind != .stampLocation && matches($0.name) }
                    .sorted(by: Self.listed)
                let trails = store.trails(in: place.id).filter { matches($0.name) }
                    .sorted { $0.name < $1.name }
                if !pois.isEmpty || !trails.isEmpty {
                    Section {
                        ForEach(pois) { poi in
                            let target = StopTarget.pointOfInterest(poi.id)
                            AddStopRow(
                                isAdded: isOnTrip(place.id, target),
                                action: { onAdd(place.id, target) }
                            ) {
                                TwoLineRow(title: poi.name, detail: poi.kind.name)
                            }
                        }
                        ForEach(trails.prefix(query.isEmpty ? 12 : 60)) { trail in
                            let target = StopTarget.trail(trail.id)
                            AddStopRow(
                                isAdded: isOnTrip(place.id, target),
                                action: { onAdd(place.id, target) }
                            ) {
                                TwoLineRow(
                                    title: trail.name,
                                    detail: "Trail · " + UnigridsFormat
                                        .distance(metres: trail.lengthMetres)
                                )
                            }
                        }
                    } header: {
                        SectionHead(place.name)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// Kind by kind, the most notable first.
    private static func listed(_ lhs: PointOfInterest, _ rhs: PointOfInterest) -> Bool {
        (lhs.kind.rawValue, lhs.rank, lhs.name) < (rhs.kind.rawValue, rhs.rank, rhs.name)
    }

    private func isOnTrip(_ placeID: UnigridsID, _ target: StopTarget) -> Bool {
        trip.orderedStops.contains { $0.place == placeID && $0.target == target }
    }
}

/// Lodging and anywhere else, found by name with MapKit's search near the trip's places,
/// each kept with the trip's place nearest to it.
private struct SearchedStopList: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let trip: Trip
    let query: String
    let onAdd: (UnigridsID, StopTarget) -> Void

    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var failed = false

    private var tripPlaces: [Place] {
        trip.orderedStops.compactMap { store.place($0.place) }
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).count < 2 {
                Text(
                    "Search for somewhere to sleep or stop on the way — a lodge, a campground "
                        + "outside the park, a town, a diner. Apple Maps answers; nothing about "
                        + "you is sent with it."
                )
                .font(UnigridStyle.proseSmall)
                .foregroundStyle(style.inkSecondary)
                .listRowBackground(Color.clear)
            } else if searching {
                ProgressView().listRowBackground(Color.clear)
            } else if failed {
                ErrorLine("Search needs a connection.").listRowBackground(Color.clear)
            } else if results.isEmpty {
                NoResults(query: query)
            }
            ForEach(results, id: \.self) { item in
                let coordinate = Coordinate(
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                )
                let parent = nearestPlace(to: coordinate)
                let name = item.name ?? "A stop"
                let target: StopTarget = isLodging(item)
                    ? .lodging(name: name, location: coordinate)
                    : .custom(name: name, location: coordinate)
                AddStopRow(
                    isAdded: trip.orderedStops.contains { $0.target == target },
                    action: { onAdd(parent?.id ?? UnigridsID(""), target) }
                ) {
                    TwoLineRow(
                        title: name,
                        detail: [
                            isLodging(item) ? "Lodging" : nil,
                            parent.map { "near \($0.name)" },
                        ]
                        .compactMap(\.self).joined(separator: " · ")
                    )
                }
            }
        }
        .listStyle(.plain)
        .task(id: query) { await search() }
    }

    private func isLodging(_ item: MKMapItem) -> Bool {
        [.hotel, .campground, .rvPark].contains(item.pointOfInterestCategory)
    }

    /// The trip's place nearest a point, or failing one within 80 km, the nearest place.
    private func nearestPlace(to point: Coordinate) -> Place? {
        let onTrip = tripPlaces
            .min { $0.centre.distance(to: point) < $1.centre.distance(to: point) }
        if let onTrip, onTrip.centre.distance(to: point) < 80000 {
            return onTrip
        }
        return store.nearest(to: point, limit: 1, tiers: [.nationalPark, .npsUnit, .statePark])
            .first
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        // Wait for the reader to stop typing.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        if let box = BoundingBox.enclosing(tripPlaces.map(\.centre))?.expanded(by: 0.5) {
            request.region = box.mkRegion
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(25))
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            failed = true
        }
    }
}

/// A row that adds its stop, and says once it has.
private struct AddStopRow<Label: View>: View {
    @Environment(\.unigrid) private var style
    let isAdded: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack {
                label()
                Spacer(minLength: 8)
                Image(isAdded ? UnigridsSymbol.seen : UnigridsSymbol.add)
                    .foregroundStyle(isAdded ? style.accent : style.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityValue(isAdded ? "On the trip" : "")
        .listRowBackground(Color.clear)
    }
}
