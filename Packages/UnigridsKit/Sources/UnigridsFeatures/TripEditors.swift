import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// MARK: - Editing

/// Create or edit a trip: name, dates and notes. A trip with dates takes its status from
/// them; one without says where it is itself.
struct TripEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style

    let trip: Trip?
    /// Called with a trip this sheet created, so the screen behind can open it.
    var onCreated: ((Trip) -> Void)?

    @State private var name = ""
    @State private var hasDates = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(4 * 86400)
    @State private var status = TripStatus.planned
    @State private var notes = ""
    @State private var error: String?

    private var cleanedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        SheetPage(
            trip == nil ? "New trip" : "Edit trip",
            kicker: trip?.name,
            actions: .confirm(
                trip == nil ? "Create" : "Save",
                enabled: !cleanedName.isEmpty,
                cancel: { dismiss() },
                action: save
            ),
            height: 560
        ) {
            Form {
                Section {
                    TextField("Name, like Utah in April", text: $name)
                        .font(UnigridStyle.rowTitle)
                } header: {
                    SectionHead("Name")
                }
                Section {
                    Toggle("Dates", isOn: $hasDates)
                        .font(UnigridStyle.rowTitle)
                    if hasDates {
                        DatePicker("Start", selection: $start, displayedComponents: .date)
                        DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                        Text("Status: " + TripStatus.on(
                            Date(),
                            start: start,
                            end: end,
                            stored: status
                        ).name)
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    } else {
                        Picker("Status", selection: $status) {
                            ForEach(TripStatus.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                    }
                } header: {
                    SectionHead("When")
                } footer: {
                    FormNote(
                        hasDates
                            ? "A dated trip is planned until it starts and done once it ends."
                            : "Without dates, say where the trip is yourself."
                    )
                }
                Section {
                    TextField("Permits to book, who is coming", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .font(UnigridStyle.proseSmall)
                } header: {
                    SectionHead("Notes")
                }
                if let error {
                    Section { ErrorLine(error) }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: load)
        // An end before the start is no trip: moving the start past it moves it along.
        .onChange(of: start) {
            if end < start {
                end = start
            }
        }
    }

    private func load() {
        guard let trip else { return }
        name = trip.name
        hasDates = trip.startDate != nil
        start = trip.startDate ?? Date()
        end = max(trip.endDate ?? start, start)
        status = trip.status
        notes = trip.notes
    }

    private func save() {
        guard !cleanedName.isEmpty else { return }
        do {
            let log = LogStore(context: context)
            if let trip {
                try log.update {
                    trip.name = cleanedName
                    trip.startDate = hasDates ? start : nil
                    trip.endDate = hasDates ? max(end, start) : nil
                    trip.status = status
                    trip.notes = notes
                }
                dismiss()
            } else {
                let created = try log.createTrip(
                    name: cleanedName,
                    startDate: hasDates ? start : nil,
                    endDate: hasDates ? max(end, start) : nil,
                    status: status
                )
                try log.update { created.notes = notes }
                dismiss()
                onCreated?(created)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A plain title over a detail, in the house type.
struct TwoLineRow: View {
    @Environment(\.unigrid) private var style
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(UnigridStyle.rowTitle)
                .foregroundStyle(style.ink)
            if !detail.isEmpty {
                Text(detail)
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }
}

/// A search with nothing to show.
struct NoResults: View {
    @Environment(\.unigrid) private var style
    let query: String

    var body: some View {
        Text(query.isEmpty ? "Nothing to show." : "Nothing matches \u{201C}\(query)\u{201D}.")
            .font(UnigridStyle.proseSmall)
            .foregroundStyle(style.inkSecondary)
            .listRowBackground(Color.clear)
    }
}

// MARK: - A stop's details

/// A stop's day, time and notes, and a way to take it off the trip.
struct StopDetailsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let stop: TripStop

    @State private var hasDay = false
    @State private var day = Date()
    @State private var hasTime = false
    @State private var notes = ""
    @State private var error: String?

    private var resolved: ResolvedStop {
        ResolvedStop(stop, store: store)
    }

    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: resolved.place)
    }

    private var zoneName: String {
        let zone = calendar.timeZone
        return zone.localizedName(for: .shortGeneric, locale: .current) ?? zone.identifier
    }

    var body: some View {
        SheetPage(
            "Stop",
            kicker: resolved.title,
            actions: .confirm("Save", cancel: { dismiss() }, action: save),
            height: 560
        ) {
            Form {
                Section {
                    Toggle("Planned for a day", isOn: $hasDay)
                        .font(UnigridStyle.rowTitle)
                    if hasDay {
                        DatePicker("Day", selection: $day, displayedComponents: .date)
                        Toggle("At a time", isOn: $hasTime)
                        if hasTime {
                            DatePicker("Time", selection: $day, displayedComponents: .hourAndMinute)
                        }
                    }
                } header: {
                    SectionHead("When")
                } footer: {
                    FormNote("Times are the place's own, \(zoneName).")
                }
                .environment(\.timeZone, calendar.timeZone)

                Section {
                    TextField(
                        "A reservation, a permit, who is driving",
                        text: $notes,
                        axis: .vertical
                    )
                    .lineLimit(2 ... 6)
                    .font(UnigridStyle.proseSmall)
                } header: {
                    SectionHead("Notes")
                }

                Section {
                    if let place = resolved.place {
                        NavigationLink {
                            PlaceDestination(placeID: place.id)
                        } label: {
                            Label(
                                place.tier.hasGuide ? "Open guide" : "Open page",
                                symbol: .openGuide
                            )
                        }
                    }
                    Button(role: .destructive, action: remove) {
                        Label("Take off the trip", symbol: .delete)
                    }
                }
                if let error {
                    Section { ErrorLine(error) }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            hasDay = stop.plannedDate != nil
            hasTime = stop.isTimed
            day = stop.plannedDate ?? stop.trip?.startDate ?? Date()
            notes = stop.notes
        }
    }

    private func save() {
        do {
            let date = hasTime ? day : UnigridsCalendar.noon(
                onDayOf: day,
                shownIn: calendar,
                in: calendar
            )
            try LogStore(context: context).update {
                stop.plannedDate = hasDay ? date : nil
                stop.isTimed = hasDay && hasTime
                stop.notes = notes
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        let title = resolved.title
        do {
            let change = try LogStore(context: context).delete(stop: stop)
            undo?.offer(change, message: "\(title) taken off the trip")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
