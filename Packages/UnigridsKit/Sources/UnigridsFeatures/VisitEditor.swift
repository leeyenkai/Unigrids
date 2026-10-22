import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Edit or delete a visit, which §9 lists under ownership of data: its day, its trip, a
/// rating and notes, and what was logged on it.
struct VisitEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    let visit: Visit

    @State private var day: Date
    @State private var notes: String
    @State private var rating: Int?
    @State private var tripID: UUID?
    @State private var confirmDelete = false
    @State private var error: String?

    init(visit: Visit) {
        self.visit = visit
        _day = State(initialValue: visit.date)
        _notes = State(initialValue: visit.notes)
        _rating = State(initialValue: visit.rating)
        _tripID = State(initialValue: visit.trip?.id)
    }

    private var place: Place? {
        store.place(visit.place)
    }

    /// Days at the place, in its own zone.
    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

    var body: some View {
        SheetPage(
            "Visit",
            kicker: place?.name ?? "Unknown place (\(visit.placeID))",
            actions: .confirm("Save", cancel: { dismiss() }, action: save),
            height: 680
        ) {
            Form {
                Section {
                    DatePicker("Day", selection: $day, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, calendar.timeZone)
                    Picker("Trip", selection: $tripID) {
                        Text("Not on a trip").tag(UUID?.none)
                        ForEach(trips) { trip in
                            Text(trip.name).tag(UUID?.some(trip.id))
                        }
                    }
                } header: {
                    SectionHead("When")
                } footer: {
                    FormNote("\(visit.source.name). A new day moves what was logged on it too.")
                }

                Section {
                    RatingPicker(rating: $rating)
                } header: {
                    SectionHead("Rating")
                }

                Section {
                    TextField("What you saw, who you were with", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .font(UnigridStyle.proseSmall)
                } header: {
                    SectionHead("Notes")
                }

                VisitContents(visit: visit, place: place, calendar: calendar) { error = $0 }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete this visit", symbol: .delete)
                    }
                }

                if let error {
                    Section { ErrorLine(error) }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Delete this visit?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteVisit() }
        } message: {
            Text(deleteMessage)
        }
    }

    /// What goes with the visit, said before it goes (SPECIFICATION.md §9: the passport and
    /// the log always agree, so a deleted visit takes its stamps).
    private var deleteMessage: String {
        let parts = [
            Self.count(visit.stamps?.count ?? 0, "stamp"),
            Self.count(visit.hikes?.count ?? 0, "hike"),
            Self.count(visit.checkIns?.count ?? 0, "check-in"),
        ].compactMap(\.self)
        guard !parts.isEmpty else { return "You can undo this straight after." }
        let list = parts.count == 1 ? parts[0]
            : parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        return "Its \(list) go with it. You can undo this straight after."
    }

    private static func count(_ count: Int, _ noun: String) -> String? {
        count == 0 ? nil : "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private func save() {
        do {
            let log = LogStore(context: context)
            // A new day keeps the time of day, so the order of what was logged holds.
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: visit.date),
                to: calendar.startOfDay(for: day)
            ).day ?? 0
            if days != 0, let moved = calendar.date(byAdding: .day, value: days, to: visit.date) {
                try log.move(visit, to: moved)
            }
            try log.update {
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
            let record = try LogStore(context: context).delete(visit: visit)
            undo?.offer(record, message: record.summary { store.place($0)?.name })
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// What was logged on a visit: check-ins with their photos, hikes, and stamps.
private struct VisitContents: View {
    @Environment(\.modelContext) private var context
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let visit: Visit
    let place: Place?
    let calendar: Calendar
    let onError: (String) -> Void

    var body: some View {
        if let checkIns = visit.checkIns, !checkIns.isEmpty {
            Section {
                ForEach(checkIns.sorted { $0.date < $1.date }) { checkIn in
                    VStack(alignment: .leading, spacing: 6) {
                        TwoLineRow(
                            title: name(for: checkIn),
                            detail: checkIn.date.formatted(
                                .dateTime.hour().minute().timeZone()
                                    .locale(.current)
                            )
                        )
                        .environment(\.timeZone, calendar.timeZone)
                        if !checkIn.photoAssetIdentifiers.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 4) {
                                    ForEach(checkIn.photoAssetIdentifiers, id: \.self) { id in
                                        PhotoThumbnail(identifier: id)
                                            .frame(width: 56, height: 56)
                                            .clipped()
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                        }
                    }
                }
            } header: {
                SectionHead("Check-ins", detail: "\(checkIns.count)")
            }
        }

        if let hikes = visit.hikes, !hikes.isEmpty {
            Section {
                ForEach(hikes.sorted { $0.date < $1.date }) { hike in
                    HStack {
                        TwoLineRow(title: trailName(hike), detail: hike.completion.name)
                        Spacer()
                        Button {
                            delete(hike)
                        } label: {
                            Image(.delete)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete this hike")
                    }
                }
            } header: {
                SectionHead("Hikes", detail: "\(hikes.count)")
            }
        }

        if let stamps = visit.stamps, !stamps.isEmpty {
            Section {
                ForEach(stamps.sorted { $0.date < $1.date }) { stamp in
                    HStack {
                        Text(stamp.date, format: UnigridsFormat.day(in: calendar))
                            .font(UnigridStyle.rowTitle)
                        if stamp.hasAmerica250Seal(at: place) {
                            Text("America 250")
                                .font(UnigridStyle.rowDetail)
                                .foregroundStyle(style.seal)
                        }
                        Spacer()
                        if stamp.isVerifiedOnSite {
                            Image(.verified)
                                .foregroundStyle(style.accent)
                                .accessibilityLabel("Stamped on site")
                        }
                    }
                }
            } header: {
                SectionHead("Stamps", detail: "\(stamps.count)")
            } footer: {
                FormNote("Stamps are removed from the passport, where they were made.")
            }
        }
    }

    private func name(for checkIn: CheckIn) -> String {
        switch checkIn.target {
        case let .pointOfInterest(id):
            store.pointsOfInterest(in: visit.place).first { $0.id == id }?.name
                ?? "Unknown sight"
        case let .trail(id):
            store.trails(in: visit.place).first { $0.id == id }?.name ?? "Unknown trail"
        case let .place(id):
            store.place(id)?.name ?? "Unknown place"
        }
    }

    private func trailName(_ hike: Hike) -> String {
        store.trails(in: visit.place).first { $0.id.rawValue == hike.trailID }?.name
            ?? "Unknown trail"
    }

    private func delete(_ hike: Hike) {
        let name = trailName(hike)
        do {
            let change = try LogStore(context: context).delete(hike: hike)
            undo?.offer(change, message: "Hike on \(name) deleted")
        } catch {
            onError(error.localizedDescription)
        }
    }
}
