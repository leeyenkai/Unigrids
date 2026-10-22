import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Manual check-in (SPECIFICATION.md §9).
///
/// Nothing is logged without the user confirming it, which is what this sheet is: the
/// confirmation. It writes once, on Save — to the day's visit if one is already logged
/// there (stamped, hiked or checked in), since the log keeps one visit per place per day.
public struct CheckInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Environment(\.undoHost) private var undoHost
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    let place: Place

    @State private var date = Date()
    private var source = VisitSource.manual
    @State private var rating: Int?
    @State private var notes = ""
    @State private var selectedPOIs: Set<UnigridsID> = []
    @State private var tripID: UUID?
    @State private var existing: Visit?
    @State private var saving = false
    @State private var error: String?

    public init(place: Place) {
        self.place = place
    }

    /// A check-in with some sights already ticked — from the 3D explorer's card, say,
    /// where the reader is looking at one sight.
    init(place: Place, preselecting pointsOfInterest: Set<UnigridsID>) {
        self.place = place
        _selectedPOIs = State(initialValue: pointsOfInterest)
    }

    /// A check-in for a visit the device noticed, dated when it noticed.
    init(place: Place, date: Date, source: VisitSource) {
        self.place = place
        self.source = source
        _date = State(initialValue: date)
    }

    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

    private var checkInTargets: [PointOfInterest] {
        store.pointsOfInterest(in: place.id)
            .filter(\.kind.isCheckInTarget)
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    /// Trips a visit can still join: the finished ones are history.
    private var openTrips: [Trip] {
        trips.filter { $0.status(on: date, calendar: calendar) != .done || $0.id == tripID }
    }

    public var body: some View {
        SheetPage(
            "Check in",
            kicker: place.name,
            actions: .confirm("Save", enabled: !saving, cancel: { dismiss() }, action: save)
        ) {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .environment(\.timeZone, calendar.timeZone)
                    .font(UnigridStyle.rowTitle)
                    if let existing {
                        Text(
                            "Adds to your visit on "
                                + existing.date.formatted(UnigridsFormat.day(in: calendar))
                        )
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                    }
                } header: {
                    SectionHead("When")
                } footer: {
                    FormNote("A visit can be back-dated for a trip you took years ago.")
                }

                if !openTrips.isEmpty {
                    Section {
                        Picker("Trip", selection: $tripID) {
                            Text("Not on a trip").tag(UUID?.none)
                            ForEach(openTrips) { trip in
                                Text(trip.name.isEmpty ? "Untitled trip" : trip.name)
                                    .tag(UUID?.some(trip.id))
                            }
                        }
                        .font(UnigridStyle.rowTitle)
                    } header: {
                        SectionHead("Trip")
                    } footer: {
                        FormNote("A visit on a trip shows in that trip's log.")
                    }
                }

                Section {
                    RatingPicker(rating: $rating)
                } header: {
                    SectionHead("Rating")
                }

                Section {
                    TextField("What do you want to remember?", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .font(UnigridStyle.proseSmall)
                } header: {
                    SectionHead("Notes")
                }

                if !checkInTargets.isEmpty {
                    Section {
                        ForEach(checkInTargets) { poi in
                            CheckInTargetRow(
                                poi: poi,
                                isSelected: selectedPOIs.contains(poi.id)
                            ) { toggle(poi.id) }
                        }
                    } header: {
                        SectionHead("Sights and visitor centres")
                    } footer: {
                        FormNote("Anything you tick becomes a check-in inside this visit.")
                    }
                }

                if let error {
                    Section {
                        ErrorLine(error)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            // An unfinished trip that already has this place as a stop is the likely home
            // for the visit.
            tripID = openTrips.first { trip in
                trip.orderedStops.contains { $0.place == place.id }
            }?.id
            findExisting()
        }
        .onChange(of: date) { findExisting() }
    }

    /// The visit already logged at the place that day, whose rating and notes the sheet
    /// shows so saving does not quietly overwrite them with blanks.
    private func findExisting() {
        let found = try? LogStore(context: context).visit(
            to: place.id,
            on: date,
            calendar: calendar
        )
        guard found?.id != existing?.id else { return }
        existing = found
        if let found {
            rating = found.rating ?? rating
            notes = found.notes.isEmpty ? notes : found.notes
            tripID = found.trip?.id ?? tripID
        }
    }

    private func toggle(_ id: UnigridsID) {
        if selectedPOIs.contains(id) {
            selectedPOIs.remove(id)
        } else {
            selectedPOIs.insert(id)
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        let log = LogStore(context: context)
        let joining = existing != nil
        do {
            let visit = try log.checkIn(
                to: place.id,
                on: date,
                source: source,
                rating: rating,
                notes: notes,
                trip: trips.first { $0.id == tripID },
                calendar: calendar
            )
            for poi in selectedPOIs {
                try log.checkIn(at: .pointOfInterest(poi), during: visit, on: date)
            }
            if joining {
                undo?.notify("Added to your visit to \(place.name)")
            } else {
                undo?.offer(
                    UndoableChange(
                        subject: .stamped(place.id),
                        takeOut: RecordIDs(visits: [visit.id])
                    ),
                    message: "Checked in at \(place.name)",
                    from: undoHost
                )
            }
            dismiss()
        } catch {
            saving = false
            self.error = "This visit could not be saved: \(error.localizedDescription)"
        }
    }
}

/// A sight or visitor centre to tick in a check-in.
private struct CheckInTargetRow: View {
    @Environment(\.unigrid) private var style
    let poi: PointOfInterest
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(poi.name)
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                    Text(poi.kind.name)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
                Spacer()
                if isSelected {
                    Image(.seen)
                        .foregroundStyle(style.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct RatingPicker: View {
    @Environment(\.unigrid) private var style
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    rating = rating == value ? nil : value
                } label: {
                    Image((rating ?? 0) >= value ? .rated : .unrated)
                        .font(.title3)
                        .foregroundStyle((rating ?? 0) >= value ? style.accent : style.inkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                .accessibilityAddTraits((rating ?? 0) >= value ? [.isSelected] : [])
            }
            Spacer()
            if rating != nil {
                Button("Clear") { rating = nil }
                    .font(UnigridStyle.rowDetail)
                    .buttonStyle(.plain)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}

/// A form section's footnote, in the house caption.
struct FormNote: View {
    @Environment(\.unigrid) private var style
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(UnigridStyle.caption)
            .foregroundStyle(style.inkSecondary)
    }
}

/// Something that went wrong, said plainly: a warning sign and the ink, not a colour alone.
struct ErrorLine: View {
    @Environment(\.unigrid) private var style
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(.warning)
        }
        .font(UnigridStyle.rowDetail)
        .foregroundStyle(style.ink)
    }
}
