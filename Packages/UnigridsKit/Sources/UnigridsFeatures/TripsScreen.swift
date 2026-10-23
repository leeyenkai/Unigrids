import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Trips: the planner and the log in one list (SPECIFICATION.md §9, §10). A trip starts
/// as a plan with an itinerary of stops, and fills with visits as the reader checks in.
public struct TripsScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Environment(AppRouter.self) private var router: AppRouter?
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var editing: Visit?
    @State private var creatingTrip = false
    @State private var importingPhotos = false
    @State private var path = NavigationPath()
    @State private var error: String?
    @State private var loggingArrival: DetectedVisits.Suggestion?

    public init() {}

    /// The trips by where they are today: under way first, then the ones to come in the
    /// order they start, then the finished ones, latest first.
    private var grouped: [(status: TripStatus, trips: [Trip])] {
        let now = Date()
        let byStatus = Dictionary(grouping: trips) { $0.status(on: now) }
        return [TripStatus.active, .planned, .done].compactMap { status in
            guard var list = byStatus[status], !list.isEmpty else { return nil }
            if status == .done {
                list.sort { Self.finished($0) > Self.finished($1) }
            } else {
                list.sort {
                    ($0.startDate ?? .distantFuture, $0.createdAt)
                        < ($1.startDate ?? .distantFuture, $1.createdAt)
                }
            }
            return (status, list)
        }
    }

    private static func finished(_ trip: Trip) -> Date {
        trip.endDate ?? trip.startDate ?? trip.createdAt
    }

    private var loose: [Visit] {
        visits.filter { $0.trip == nil }
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        BandHeader(
                            "Trips",
                            kicker: "\(trips.count) trip\(trips.count == 1 ? "" : "s") · "
                                + "\(visits.count) visit\(visits.count == 1 ? "" : "s") logged"
                        )
                        Button {
                            creatingTrip = true
                        } label: {
                            Label("New trip", symbol: .add)
                        }
                        .buttonStyle(BrochureButtonStyle(.primary))
                        .padding(UnigridStyle.pageMargin)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                DetectedVisitsSection(visits: visits) { loggingArrival = $0 }

                if trips.isEmpty, visits.isEmpty {
                    Section {
                        EmptyLogNote()
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(grouped, id: \.status) { group in
                    tripSection(group.status.name, trips: group.trips)
                }

                if !loose.isEmpty {
                    Section {
                        ForEach(loose) { visit in
                            VisitRow(visit: visit) { editing = visit }
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(visit)
                                    } label: {
                                        Label("Delete", symbol: .delete)
                                    }
                                }
                                .contextMenu {
                                    Button { editing = visit } label: {
                                        Label("Edit", symbol: .edit)
                                    }
                                    Button(role: .destructive) {
                                        delete(visit)
                                    } label: {
                                        Label("Delete", symbol: .delete)
                                    }
                                }
                        }
                    } header: {
                        SectionHead(
                            trips.isEmpty ? "Visits" : "Visits not on a trip",
                            detail: "\(loose.count)"
                        )
                    }
                }
            }
            .listStyle(.plain)
            .paperPage()
            .navigationTitle("Trips")
            .toolbarTitleDisplayMode(.inline)
            #if os(iOS)
                .toolbar { SettingsToolbarItem() }
            #endif
                .toolbar {
                    ToolbarItem {
                        Button {
                            importingPhotos = true
                        } label: {
                            Label("Import from Photos", symbol: .importPhotos)
                        }
                        .help("Import from Photos")
                    }
                }
                .unigridsSheet(isPresented: $importingPhotos) {
                    PhotoImportScreen()
                }
                .onAppear {
                    let first = grouped.first?.trips.first
                    if DebugLaunch.opensFirstTrip, path.isEmpty, let first {
                        path.append(first)
                    }
                }
                .navigationDestination(for: Trip.self) { trip in
                    TripDetailScreen(trip: trip)
                }
                .navigationDestination(for: UnigridsID.self) { id in
                    PlaceDestination(placeID: id)
                }
                .unigridsSheet(item: $editing) { visit in
                    VisitEditor(visit: visit)
                }
                .unigridsSheet(item: $loggingArrival) { suggestion in
                    ArrivalCheckIn(suggestion: suggestion)
                }
                .onChange(of: router?.pending, initial: true) { takeRoute() }
                .onChange(of: scenePhase) { takeRoute() }
                .unigridsSheet(isPresented: $creatingTrip) {
                    // A new trip opens, so its stops can be added straight away.
                    TripEditor(trip: nil) { path.append($0) }
                }
                .alert("Could not save", isPresented: Binding(
                    get: { error != nil },
                    set: {
                        if !$0 {
                            error = nil
                        }
                    }
                )) {
                    Button("OK") { error = nil }
                } message: {
                    Text(error ?? "")
                }
        }
    }

    private func tripSection(_ title: String, trips: [Trip]) -> some View {
        Section {
            ForEach(trips) { trip in
                NavigationLink(value: trip) {
                    TripRow(trip: trip)
                }
                .listRowBackground(Color.clear)
            }
        } header: {
            SectionHead(title, detail: "\(trips.count)")
        }
    }

    /// A notification's route, if it is this tab's to show.
    private func takeRoute() {
        guard scenePhase == .active, let route = router?.pending else { return }
        switch route {
        case let .trip(id):
            guard let trip = trips.first(where: { $0.id == id }) else { return }
            router?.pending = nil
            path = NavigationPath()
            path.append(trip)
        case let .arrival(placeID, date):
            router?.pending = nil
            loggingArrival = DetectedVisits.Suggestion(placeID: placeID, date: date)
        case .place:
            return
        }
    }

    private func delete(_ visit: Visit) {
        do {
            let record = try LogStore(context: context).delete(visit: visit)
            undo?.offer(record, message: record.summary { store.place($0)?.name })
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The log sheet for a detected arrival, or a note if the place has left the dataset.
private struct ArrivalCheckIn: View {
    @Environment(\.referenceStore) private var store
    let suggestion: DetectedVisits.Suggestion

    var body: some View {
        if let place = store.place(UnigridsID(suggestion.placeID)) {
            CheckInSheet(place: place, date: suggestion.date, source: .autoDetected)
        } else {
            ContentUnavailableView(
                "Unknown place",
                systemImage: UnigridsSymbol.unknownPlace.systemName,
                description: Text("This place is no longer in the dataset.")
            )
        }
    }
}

struct EmptyLogNote: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing here yet.")
                .font(UnigridStyle.rowTitle)
                .foregroundStyle(style.ink)
            Text(
                "Start a new trip, or check in from a map card or a park guide. Stamping "
                    + "the passport logs a visit too, so the trip log and the passport always "
                    + "agree."
            )
            .font(UnigridStyle.proseSmall)
            .foregroundStyle(style.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

/// A trip in the list: its name, dates, and its places as a row of markers.
struct TripRow: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.name)
                .font(UnigridStyle.rowTitle)
                .foregroundStyle(style.ink)
            Text(detail)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
            let places = places
            if !places.isEmpty {
                HStack(spacing: 4) {
                    ForEach(places.prefix(14)) { place in
                        PlaceMarker(tier: place.tier, tint: style.siteTint(for: place))
                    }
                    if places.count > 14 {
                        Text("+\(places.count - 14)")
                            .font(UnigridStyle.dataLabel)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                .accessibilityLabel(places.map(\.name).joined(separator: ", "))
            }
        }
        .padding(.vertical, 4)
    }

    /// Each place once, though a trip may have a park and three of its sights.
    private var places: [Place] {
        var seen: Set<UnigridsID> = []
        return trip.orderedStops
            .filter { seen.insert($0.place).inserted }
            .compactMap { store.place($0.place) }
    }

    private var detail: String {
        var parts: [String] = []
        if let range = TripDates.range(trip) {
            parts.append(range)
        }
        let stops = trip.orderedStops.count
        parts.append("\(stops) stop\(stops == 1 ? "" : "s")")
        let visits = trip.visits?.count ?? 0
        if visits > 0 {
            parts.append("\(visits) visit\(visits == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}

/// A trip's dates in a line: "12–18 Jun 2026", or "30 Jun – 4 Jul 2026".
enum TripDates {
    static func range(_ trip: Trip, calendar: Calendar = .unigrids) -> String? {
        guard let start = trip.startDate else { return nil }
        let end = max(trip.endDate ?? start, start)
        if UnigridsCalendar.isSameDay(start, end, calendar: calendar) {
            return start.formatted(UnigridsFormat.day(in: calendar))
        }
        var style = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return (start ..< end).formatted(style)
    }
}

/// A logged visit: where, when, how it was logged, and what was checked in.
struct VisitRow: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let visit: Visit
    let onEdit: () -> Void

    var body: some View {
        let place = store.place(visit.place)
        Button(action: onEdit) {
            HStack(spacing: 12) {
                if let place {
                    PlaceMarker(
                        tier: place.tier,
                        tint: style.siteTint(for: place),
                        status: .visited
                    )
                    .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 3) {
                    // A visit outlives the reference data it points at, so an unresolved
                    // place renders as unknown rather than disappearing (AGENTS.md §4).
                    Text(place?.name ?? "Unknown place (\(visit.placeID))")
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(place == nil ? style.inkSecondary : style.ink)
                    HStack(spacing: 6) {
                        Text(
                            visit.date,
                            format: UnigridsFormat.day(in: UnigridsCalendar.gregorian(at: place))
                        )
                        Text("·")
                        Text(visit.source.name)
                        if let count = visit.checkIns?.count, count > 0 {
                            Text("·")
                            Text("\(count) check-in\(count == 1 ? "" : "s")")
                        }
                        if let stamps = visit.stamps?.count, stamps > 0 {
                            StampIcon()
                                .accessibilityLabel("Stamped")
                        }
                    }
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
                }
                Spacer()
                if let rating = visit.rating {
                    HStack(spacing: 1) {
                        ForEach(0 ..< rating, id: \.self) { _ in
                            Image(.rated)
                        }
                    }
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.ink)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(rating) of 5 stars")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
