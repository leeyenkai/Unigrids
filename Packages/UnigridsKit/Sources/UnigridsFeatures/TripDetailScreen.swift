import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// One trip: its route on a map, its itinerary in order, and the visits logged on it
/// (SPECIFICATION.md §10).
struct TripDetailScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Environment(AlertsCenter.self) private var alerts: AlertsCenter?
    @Environment(UndoCenter.self) private var undo: UndoCenter?

    let trip: Trip

    @State private var driveTimes = DriveTimes()
    @State private var forecasts = Forecasts()
    @State private var addingStop = false
    @State private var editingTrip = false
    @State private var confirmDelete = false
    @State private var error: String?

    private var stops: [(stop: TripStop, place: Place?)] {
        trip.orderedStops.map { ($0, store.place($0.place)) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    BandHeader(trip.name, kicker: kicker)
                    if stops.contains(where: { $0.place != nil }) {
                        TripMap(places: knownPlaces, roads: roads)
                            .frame(height: 280)
                    }
                    TripFigures(trip: trip, places: knownPlaces, legs: routedLegs)
                        .padding(UnigridStyle.pageMargin)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            Section {
                if stops.isEmpty {
                    Text(
                        "No stops yet. Add the parks you mean to see, "
                            + "in the order you mean to see them."
                    )
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.inkSecondary)
                    .listRowBackground(Color.clear)
                }
                ForEach(Array(stops.enumerated()), id: \.element.stop.id) { index, entry in
                    VStack(alignment: .leading, spacing: 8) {
                        let previous = index > 0 ? stops[index - 1].place : nil
                        if let previous, let place = entry.place {
                            LegLine(
                                leg: driveTimes.leg(from: previous.id, to: place.id),
                                failed: driveTimes.hasFailed(from: previous.id, to: place.id),
                                straightLine: previous.centre.distance(to: place.centre)
                            )
                        }
                        StopRow(number: index + 1, stop: entry.stop, place: entry.place, trip: trip)
                        if let place = entry.place {
                            StopExtras(
                                weather: entry.stop.plannedDate.flatMap {
                                    forecasts.forecast(for: place, on: $0)
                                },
                                flags: StopFlag.flags(
                                    for: place,
                                    on: entry.stop.plannedDate,
                                    alerts: alerts,
                                    guide: store.guide(for: place.id)
                                )
                            )
                            .padding(.leading, 34)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
                .onMove(perform: move)
                .onDelete(perform: deleteStops)

                Button {
                    addingStop = true
                } label: {
                    Label("Add a stop", systemImage: "plus")
                }
                .buttonStyle(BrochureButtonStyle(.secondary))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } header: {
                SectionHead("Itinerary", detail: "\(stops.count)")
            }

            TripDaysSection(days: days)

            TripRemindersSection(trip: trip)

            if let visits = trip.visits, !visits.isEmpty {
                Section {
                    ForEach(visits.sorted { $0.date < $1.date }) { visit in
                        VisitRow(visit: visit) {}
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    SectionHead("Logged on this trip", detail: "\(visits.count)")
                }
            }

            if !trip.notes.isEmpty {
                Section {
                    Text(trip.notes)
                        .font(UnigridStyle.proseSmall)
                        .foregroundStyle(style.ink)
                        .listRowBackground(Color.clear)
                } header: {
                    SectionHead("Notes")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Delete this trip")
                        .font(UnigridStyle.action)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .listRowBackground(Color.clear)
            } footer: {
                Text("Deleting a trip keeps its visits in your log.")
                    .font(UnigridStyle.caption)
            }
        }
        .listStyle(.plain)
        .paperPage()
        .navigationTitle(trip.name)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem {
                Button("Edit") { editingTrip = true }
            }
            if let file = calendarFile {
                ToolbarItem {
                    ShareLink(item: file) {
                        Label("Add to Calendar", systemImage: "calendar.badge.plus")
                    }
                }
            }
            if let file = gpxFile {
                ToolbarItem {
                    ShareLink(item: file) {
                        Label(
                            "Export GPX",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                        )
                    }
                }
            }
        }
        .task(id: knownPlaces.map(\.id)) {
            await driveTimes.route(knownPlaces, store: store)
            await forecasts.load(forecastable)
        }
        .task { await alerts?.refreshIfStale() }
        .unigridsSheet(isPresented: $addingStop) { StopPicker(trip: trip) }
        .unigridsSheet(isPresented: $editingTrip) { TripEditor(trip: trip) }
        .confirmationDialog(
            "Delete \(trip.name)?", isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("Delete trip", role: .destructive, action: deleteTrip)
        }
        .alert("Could not save", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var knownPlaces: [Place] {
        stops.compactMap(\.place)
    }

    /// Legs MapKit has routed, between consecutive known stops.
    private var routedLegs: [DriveLeg] {
        zip(knownPlaces, knownPlaces.dropFirst()).compactMap { from, to in
            driveTimes.leg(from: from.id, to: to.id).map {
                DriveLeg(from: from.id, to: to.id, seconds: $0.seconds, metres: $0.metres)
            }
        }
    }

    private var roads: [[Coordinate]] {
        zip(knownPlaces, knownPlaces.dropFirst()).compactMap { from, to in
            driveTimes.leg(from: from.id, to: to.id)?.path
        }
    }

    private var days: [TripDay] {
        TripSchedule.days(
            stops: stops.compactMap { entry in
                entry.place.map { (id: $0.id, date: entry.stop.plannedDate) }
            },
            legs: routedLegs
        )
    }

    /// Stops planned within the sixteen days a forecast reaches.
    private var forecastable: [Place] {
        let horizon = Date().addingTimeInterval(16 * 86400)
        return stops.compactMap { entry in
            guard let day = entry.stop.plannedDate, day <= horizon,
                  day >= Calendar.current.startOfDay(for: Date()) else { return nil }
            return entry.place
        }
    }

    private var kicker: String {
        var parts = [trip.status.name]
        if let start = trip.startDate {
            parts.append(start.formatted(.dateTime.day().month(.abbreviated).year()))
        }
        return parts.joined(separator: " · ")
    }

    /// The itinerary as an .ics file, for stops that have a date. Written to the temporary
    /// directory each time it is asked for; it is a hand-off, not a store.
    private var calendarFile: URL? {
        let events = stops.compactMap { entry -> TripCalendar.Event? in
            guard let day = entry.stop.plannedDate else { return nil }
            let title = entry.place.map { "\($0.name) \($0.designation)" } ?? "Trip stop"
            return TripCalendar.Event(title: title, day: day, notes: entry.stop.notes)
        }
        guard !events.isEmpty else { return nil }
        let text = TripCalendar.document(
            name: trip.name, events: events, identifier: trip.id.uuidString, stamp: Date()
        )
        let safeName = trip.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "trip" : safeName).ics")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// The trip's places as GPX waypoints, in itinerary order, for any mapping app.
    private var gpxFile: URL? {
        let waypoints = stops.compactMap { entry -> TripGPX.Waypoint? in
            guard let place = entry.place else { return nil }
            return TripGPX.Waypoint(
                name: "\(place.name) \(place.designation)",
                coordinate: place.centre,
                date: entry.stop.plannedDate,
                note: entry.stop.notes
            )
        }
        guard !waypoints.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileStem).gpx")
        do {
            try TripGPX.document(name: trip.name, waypoints: waypoints)
                .write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private var fileStem: String {
        let stem = trip.name.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return stem.isEmpty ? "trip" : stem
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = trip.orderedStops
        ordered.move(fromOffsets: source, toOffset: destination)
        do {
            try LogStore(context: context).reorder(ordered)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteStops(at offsets: IndexSet) {
        let ordered = trip.orderedStops
        do {
            let log = LogStore(context: context)
            for offset in offsets {
                try log.delete(stop: ordered[offset])
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteTrip() {
        do {
            let record = try LogStore(context: context).delete(trip: trip)
            undo?.offer(record, message: record.summary { store.place($0)?.name })
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The trip in figures: stops, states, days, and straight-line distance.
struct TripFigures: View {
    let trip: Trip
    let places: [Place]
    var legs: [DriveLeg] = []

    var body: some View {
        let distance = TripRoute.totalDistance(places.map(\.centre))
        let states = Set(places.flatMap { $0.states.map(\.code) })
        let allRouted = places.count > 1 && legs.count == places.count - 1
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 110), spacing: 14, alignment: .top)],
            alignment: .leading,
            spacing: 14
        ) {
            FigureBlock(value: "\(places.count)", label: "Stops", compact: true)
            FigureBlock(value: "\(states.count)", label: "States", compact: true)
            if let days {
                FigureBlock(value: "\(days)", label: days == 1 ? "Day" : "Days", compact: true)
            }
            if allRouted {
                FigureBlock(
                    value: UnigridsFormat.duration(legs.reduce(0) { $0 + $1.seconds }),
                    label: "Driving",
                    compact: true
                )
                FigureBlock(
                    value: UnigridsFormat.distance(metres: legs.reduce(0) { $0 + $1.metres }),
                    label: "By road",
                    compact: true
                )
            } else if distance > 0 {
                FigureBlock(
                    value: UnigridsFormat.distance(metres: distance),
                    label: "Straight line",
                    compact: true
                )
            }
        }
    }

    private var days: Int? {
        guard let start = trip.startDate, let end = trip.endDate else { return nil }
        let count = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: start),
            to: Calendar.current.startOfDay(for: end)
        ).day ?? 0
        return max(count + 1, 1)
    }
}

/// One stop: its number, the place, the day, and whether it has been visited on this trip.
struct StopRow: View {
    @Environment(\.unigrid) private var style
    @Environment(\.modelContext) private var context
    let number: Int
    let stop: TripStop
    let place: Place?
    let trip: Trip

    @State private var editingDate = false

    var body: some View {
        HStack(spacing: 12) {
            SightNumber(number: number, isSelected: visited)
            NavigationLink(value: stop.place) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place?.name ?? "Unknown place")
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                    Text(detail)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
            }
        }
        .contextMenu {
            Button("Set the day") { editingDate = true }
        }
        .swipeActions(edge: .leading) {
            Button("Day") { editingDate = true }
        }
        .unigridsSheet(isPresented: $editingDate) {
            StopDateSheet(stop: stop)
        }
    }

    private var visited: Bool {
        (trip.visits ?? []).contains { $0.place == stop.place }
    }

    private var detail: String {
        var parts: [String] = []
        if let place {
            parts.append(place.designation)
        }
        if let day = stop.plannedDate {
            parts.append(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
        }
        if visited {
            parts.append("Visited")
        }
        return parts.joined(separator: " · ")
    }
}

struct StopDateSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let stop: TripStop
    @State private var day = Date()
    @State private var hasDay = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Planned for a day", isOn: $hasDay)
                if hasDay {
                    DatePicker("Day", selection: $day, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Stop")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        _ = try? LogStore(context: context).update {
                            stop.plannedDate = hasDay ? day : nil
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                hasDay = stop.plannedDate != nil
                day = stop.plannedDate ?? stop.trip?.startDate ?? Date()
            }
        }
        .presentationDetents([.medium])
    }
}
