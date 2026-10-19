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

    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var editing: Visit?
    @State private var creatingTrip = false
    @State private var error: String?

    public init() {}

    private var openTrips: [Trip] {
        trips.filter { $0.status != .done }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private var doneTrips: [Trip] {
        trips.filter { $0.status == .done }
    }

    private var loose: [Visit] {
        visits.filter { $0.trip == nil }
    }

    public var body: some View {
        NavigationStack {
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
                            Label("Plan a trip", systemImage: "plus")
                        }
                        .buttonStyle(BrochureButtonStyle(.primary))
                        .padding(UnigridStyle.pageMargin)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if trips.isEmpty, visits.isEmpty {
                    Section {
                        EmptyLogNote()
                            .listRowBackground(Color.clear)
                    }
                }

                if !openTrips.isEmpty {
                    tripSection("Planning", trips: openTrips)
                }
                if !doneTrips.isEmpty {
                    tripSection("Done", trips: doneTrips)
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
                                        Label("Delete", systemImage: "trash")
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
            .navigationDestination(for: Trip.self) { trip in
                TripDetailScreen(trip: trip)
            }
            .navigationDestination(for: UnigridsID.self) { id in
                PlaceDestination(placeID: id)
            }
            .sheet(item: $editing) { visit in
                VisitEditor(visit: visit)
            }
            .sheet(isPresented: $creatingTrip) {
                TripEditor(trip: nil)
            }
            .alert("Could not save", isPresented: .constant(error != nil)) {
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

    private func delete(_ visit: Visit) {
        do {
            try LogStore(context: context).delete(visit)
        } catch {
            self.error = error.localizedDescription
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
                "Plan a trip, or check in from a map card or a park guide. Stamping the "
                    + "passport logs a visit too, so the trip log and the passport always agree."
            )
            .font(UnigridStyle.proseSmall)
            .foregroundStyle(style.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

/// A trip in the list: its name, dates, and its stops as a row of markers.
struct TripRow: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.name)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Spacer()
                Kicker(trip.status.name)
            }
            Text(detail)
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
            let places = trip.orderedStops.compactMap { store.place($0.place) }
            if !places.isEmpty {
                HStack(spacing: 4) {
                    ForEach(places.prefix(14)) { place in
                        PlaceMarker(tier: place.tier, tint: style.agencyTint(for: place))
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

    private var detail: String {
        var parts: [String] = []
        if let start = trip.startDate {
            var range = start.formatted(.dateTime.day().month(.abbreviated))
            if let end = trip.endDate, !Calendar.current.isDate(end, inSameDayAs: start) {
                range += "–" + end.formatted(.dateTime.day().month(.abbreviated).year())
            } else {
                range += " " + start.formatted(.dateTime.year())
            }
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
                        tint: style.agencyTint(for: place),
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
                        Text(visit.date, format: .dateTime.day().month(.abbreviated).year())
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
                    Text(String(repeating: "★", count: rating))
                        .font(.caption)
                        .foregroundStyle(style.ink)
                        .accessibilityLabel("\(rating) stars")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visit editor

/// Edit or delete anything, which §9 lists under ownership of data.
struct VisitEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    let visit: Visit

    @State private var date: Date
    @State private var notes: String
    @State private var rating: Int?
    @State private var tripID: UUID?
    @State private var confirmDelete = false
    @State private var error: String?

    init(visit: Visit) {
        self.visit = visit
        _date = State(initialValue: visit.date)
        _notes = State(initialValue: visit.notes)
        _rating = State(initialValue: visit.rating)
        _tripID = State(initialValue: visit.trip?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Picker("Trip", selection: $tripID) {
                        Text("Not on a trip").tag(UUID?.none)
                        ForEach(trips) { trip in
                            Text(trip.name).tag(UUID?.some(trip.id))
                        }
                    }
                } header: {
                    Text(store.place(visit.place)?.name ?? visit.placeID)
                }

                Section("Rating") {
                    RatingPicker(rating: $rating)
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                }

                if let checkIns = visit.checkIns, !checkIns.isEmpty {
                    Section("Check-ins") {
                        ForEach(checkIns.sorted { $0.date < $1.date }) { checkIn in
                            Text(name(for: checkIn))
                                .font(.subheadline)
                        }
                    }
                }

                if let stamps = visit.stamps, !stamps.isEmpty {
                    Section("Stamps") {
                        ForEach(stamps) { stamp in
                            HStack {
                                Text(
                                    stamp.date,
                                    format: .dateTime.day().month(.abbreviated).year()
                                )
                                if stamp.hasAmerica250Seal() {
                                    Text("America 250")
                                        .font(.caption)
                                        .foregroundStyle(style.seal)
                                }
                                Spacer()
                                if stamp.isVerifiedOnSite {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.tint)
                                        .accessibilityLabel("Verified on site")
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Delete this visit", role: .destructive) {
                        confirmDelete = true
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(style.seal)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Visit")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .confirmationDialog(
                "Delete this visit?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteVisit() }
            } message: {
                Text("Its check-ins go with it. Passport stamps stay in the passport.")
            }
        }
    }

    private func name(for checkIn: CheckIn) -> String {
        switch checkIn.target {
        case let .pointOfInterest(id):
            store.pointsOfInterest(in: visit.place).first { $0.id == id }?.name
                ?? id.rawValue
        case let .trail(id):
            store.trails(in: visit.place).first { $0.id == id }?.name ?? id.rawValue
        case let .place(id):
            store.place(id)?.name ?? id.rawValue
        }
    }

    private func save() {
        do {
            try LogStore(context: context).update {
                visit.date = date
                visit.notes = notes
                visit.rating = rating
                visit.trip = trips.first { $0.id == tripID }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteVisit() {
        do {
            try LogStore(context: context).delete(visit)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
