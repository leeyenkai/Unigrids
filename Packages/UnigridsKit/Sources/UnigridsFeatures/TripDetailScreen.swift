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

    let trip: Trip

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
                        TripMap(places: stops.compactMap(\.place))
                            .frame(height: 260)
                    }
                    TripFigures(trip: trip, places: stops.compactMap(\.place))
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
                    StopRow(number: index + 1, stop: entry.stop, place: entry.place, trip: trip)
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
        }
        .sheet(isPresented: $addingStop) { StopPicker(trip: trip) }
        .sheet(isPresented: $editingTrip) { TripEditor(trip: trip) }
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
                try log.delete(ordered[offset])
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteTrip() {
        do {
            try LogStore(context: context).delete(trip)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The trip's stops on a map, numbered, joined in order by a straight rule.
struct TripMap: View {
    @Environment(\.unigrid) private var style
    let places: [Place]

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if places.count > 1 {
                MapPolyline(coordinates: places.map(\.centre.clCoordinate))
                    .stroke(style.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(places.enumerated()), id: \.offset) { index, place in
                Annotation(place.name, coordinate: place.centre.clCoordinate) {
                    SightNumber(number: index + 1)
                }
            }
        }
        .mapStyle(.standard(
            elevation: .realistic,
            emphasis: .muted,
            pointsOfInterest: .excludingAll
        ))
        .onAppear { frameStops(animated: false) }
        .onChange(of: places.map(\.id)) { frameStops(animated: true) }
    }

    /// Fit every stop, refitting as stops are added, removed or reordered. A single stop
    /// gets a regional view rather than a street-level one.
    private func frameStops(animated: Bool) {
        guard let box = BoundingBox.enclosing(places.map(\.centre))?.expanded(by: 0.25) else {
            return
        }
        let region = MKCoordinateRegion(
            center: box.centre.clCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(box.north - box.south, 1.5),
                longitudeDelta: max(box.east - box.west, 1.5)
            )
        )
        if animated {
            withAnimation { position = .region(region) }
        } else {
            position = .region(region)
        }
    }
}

/// The trip in figures: stops, states, days, and straight-line distance.
struct TripFigures: View {
    let trip: Trip
    let places: [Place]

    var body: some View {
        let distance = TripRoute.totalDistance(places.map(\.centre))
        let states = Set(places.flatMap { $0.states.map(\.code) })
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
            if distance > 0 {
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
        .sheet(isPresented: $editingDate) {
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
