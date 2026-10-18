import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The log (SPECIFICATION.md §9, §10).
///
/// A trip holds park visits, and each visit holds check-ins. The planner's four tools —
/// itineraries, alerts, permits and weather — arrive in 1.0.0, so this milestone shows
/// the log honestly rather than a planner that cannot plan.
public struct TripsScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context

    @Query(sort: \Visit.date, order: .reverse) private var visits: [Visit]
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    @State private var editing: Visit?
    @State private var error: String?

    public init() {}

    private var loose: [Visit] {
        visits.filter { $0.trip == nil }
    }

    public var body: some View {
        NavigationStack {
            List {
                if visits.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No visits yet", systemImage: "suitcase")
                        } description: {
                            Text(
                                "Check in from a map pin, a park guide or the passport, "
                                    + "and it shows up here."
                            )
                        }
                    }
                }

                ForEach(trips) { trip in
                    Section {
                        ForEach((trip.visits ?? []).sorted { $0.date > $1.date }) { visit in
                            visitRow(visit)
                        }
                    } header: {
                        HStack {
                            Text(trip.name)
                            Spacer()
                            Text(trip.status.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !loose.isEmpty {
                    Section(trips.isEmpty ? "Visits" : "Not on a trip") {
                        ForEach(loose) { visit in
                            visitRow(visit)
                        }
                    }
                }

                Section {
                    PlannerPendingRow()
                }
            }
            .navigationTitle("Trips")
            .sheet(item: $editing) { visit in
                VisitEditor(visit: visit)
            }
            .alert("Could not save", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func visitRow(_ visit: Visit) -> some View {
        let place = store.place(visit.place)
        return Button {
            editing = visit
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // A visit outlives the reference data it points at, so an unresolved
                    // place renders as unknown rather than disappearing (AGENTS.md §4).
                    Text(place?.name ?? "Unknown place (\(visit.placeID))")
                        .font(.body.weight(.medium))
                        .foregroundStyle(place == nil ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Text(visit.date, format: .dateTime.day().month(.abbreviated).year())
                        Text("·")
                        Text(visit.source.name)
                        if let count = visit.checkIns?.count, count > 0 {
                            Text("·")
                            Text("\(count) check-in\(count == 1 ? "" : "s")")
                        }
                        if let stamps = visit.stamps?.count, stamps > 0 {
                            Image(systemName: "stamp")
                                .accessibilityLabel("Stamped")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if let rating = visit.rating {
                    HStack(spacing: 1) {
                        ForEach(0 ..< rating, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                    .accessibilityLabel("\(rating) stars")
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                delete(visit)
            } label: {
                Label("Delete", systemImage: "trash")
            }
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

/// Says plainly what the planner will do, rather than offering a button that does nothing
/// (AGENTS.md §10).
struct PlannerPendingRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Planner arrives in 1.0", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.medium))
            Text(
                "Multi-day itineraries with drive times, live NPS alerts, permit and "
                    + "timed-entry reminders, and weather against crowds by month."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

/// Edit or delete anything, which §9 lists under ownership of data.
struct VisitEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store

    let visit: Visit

    @State private var date: Date
    @State private var notes: String
    @State private var rating: Int?
    @State private var error: String?

    init(visit: Visit) {
        self.visit = visit
        _date = State(initialValue: visit.date)
        _notes = State(initialValue: visit.notes)
        _rating = State(initialValue: visit.rating)
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
                                        .foregroundStyle(UnigridStyle.sealRed)
                                }
                                Spacer()
                                if stamp.isVerifiedOnSite {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(UnigridStyle.parkGreen)
                                        .accessibilityLabel("Verified on site")
                                }
                            }
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
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
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
