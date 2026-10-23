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
    @Environment(\.undoHost) private var undoHost

    let trip: Trip

    @State private var driveTimes = DriveTimes()
    @State private var forecasts = Forecasts()
    @State private var addingStop = false
    @State private var editingTrip = false
    @State private var detailing: TripStop?
    @State private var editingVisit: Visit?
    @State private var confirmDelete = false
    @State private var reordering = false
    @State private var sharingCard = false
    @State private var error: String?

    private var stops: [ResolvedStop] {
        trip.orderedStops.map { ResolvedStop($0, store: store) }
    }

    var body: some View {
        List {
            Section {
                TripHeader(trip: trip, stops: stops, legs: routedLegs, roads: roads)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ItinerarySection(
                stops: stops,
                trip: trip,
                driveTimes: driveTimes,
                forecasts: forecasts,
                reordering: $reordering,
                onAdd: { addingStop = true },
                onDetails: { detailing = $0 },
                onMove: move,
                onDelete: deleteStops
            )

            TripDaysSection(days: days, stops: stops)

            TripRemindersSection(trip: trip)

            if let visits = trip.visits, !visits.isEmpty {
                Section {
                    ForEach(visits.sorted { $0.date < $1.date }) { visit in
                        VisitRow(visit: visit) { editingVisit = visit }
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
                    Label("Delete this trip", symbol: .delete)
                }
                .buttonStyle(BrochureButtonStyle(.secondary))
                .listRowBackground(Color.clear)
                ListNotes { Text("Deleting a trip keeps its visits in your log.") }
            }
        }
        .listStyle(.plain)
        .paperPage()
        // On the Mac the window takes the trip's name: the band says it on the page, and the
        // title bar would otherwise say only "Unigrids".
        #if os(iOS)
            .environment(\.editMode, .constant(reordering ? .active : .inactive))
        #else
            .navigationTitle(trip.name.isEmpty ? "Trip" : trip.name)
        #endif
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .task(id: RouteKey(stops: stops.map(\.routeKey), attempt: driveTimes.attempt)) {
                await driveTimes.route(stops, store: store)
                await forecasts.load(forecastable)
            }
            .task { await alerts?.refreshIfStale() }
            .unigridsSheet(isPresented: $addingStop) { StopPicker(trip: trip) }
            .unigridsSheet(isPresented: $editingTrip) { TripEditor(trip: trip) }
            .unigridsSheet(item: $detailing) { StopDetailsSheet(stop: $0) }
            .unigridsSheet(item: $editingVisit) { VisitEditor(visit: $0) }
            .unigridsSheet(isPresented: $sharingCard) {
                ShareCardSheet(title: trip.name.isEmpty ? "My trip" : trip.name, card: tripCard)
            }
            .confirmationDialog(
                "Delete \(trip.name.isEmpty ? "this trip" : trip.name)?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete trip", role: .destructive, action: deleteTrip)
            } message: {
                Text("Its stops and reminders go with it; its visits stay in your log.")
            }
            .alert("Could not save", isPresented: errorShown) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                editingTrip = true
            } label: {
                Label("Edit trip", symbol: .edit)
            }
            .help("Edit trip")
        }
        if !stops.isEmpty {
            ToolbarItem {
                Menu {
                    if let calendar = exports.calendar {
                        ShareLink(item: calendar, preview: SharePreview("\(trip.name).ics")) {
                            Label("Add to Calendar", symbol: .addToCalendar)
                        }
                    }
                    if let gpx = exports.gpx {
                        ShareLink(item: gpx, preview: SharePreview("\(trip.name).gpx")) {
                            Label("Export GPX", symbol: .exportRoute)
                        }
                    }
                    Button { sharingCard = true } label: {
                        Label("Share a card", symbol: .share)
                    }
                } label: {
                    Label("Share", symbol: .share)
                }
                .help("Share")
            }
        }
    }

    private var tripCard: TripShareCard {
        let states = Set(stops.compactMap(\.place).flatMap { $0.states.map(\.code) })
        var figures = [
            (value: "\(stops.count)", label: stops.count == 1 ? "Stop" : "Stops"),
            (value: "\(states.count)", label: states.count == 1 ? "State" : "States"),
        ]
        if routedLegs.count == stops.count - 1, !routedLegs.isEmpty {
            figures.append((
                value: UnigridsFormat.distance(metres: routedLegs.reduce(0) { $0 + $1.metres }),
                label: "By road"
            ))
        }
        return TripShareCard(
            name: trip.name.isEmpty ? "My trip" : trip.name,
            dates: TripDates.range(trip),
            stops: stops.map { entry in
                let day = entry.stop.plannedDate.map {
                    $0
                        .formatted(UnigridsFormat
                            .weekday(in: UnigridsCalendar.gregorian(at: entry.place)))
                }
                return (
                    title: entry.title,
                    detail: [day, entry.subtitle].compactMap(\.self)
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                )
            },
            figures: figures
        )
    }

    private var errorShown: Binding<Bool> {
        Binding(get: { error != nil }, set: {
            if !$0 {
                error = nil
            }
        })
    }

    /// Legs MapKit has routed, between consecutive stops.
    private var routedLegs: [DriveLeg] {
        zip(stops, stops.dropFirst()).compactMap { from, to in
            driveTimes.leg(from: from, to: to).map {
                DriveLeg(
                    from: from.scheduleID, to: to.scheduleID,
                    seconds: $0.seconds, metres: $0.metres
                )
            }
        }
    }

    private var roads: [[Coordinate]] {
        zip(stops, stops.dropFirst()).compactMap { driveTimes.leg(from: $0, to: $1)?.path }
    }

    private var days: [TripDay] {
        TripSchedule.days(
            stops: stops.map { (id: $0.scheduleID, date: $0.stop.plannedDate) },
            legs: routedLegs
        )
    }

    /// Places with a stop planned within the sixteen days a forecast reaches.
    private var forecastable: [Place] {
        let horizon = Date().addingTimeInterval(16 * 86400)
        let today = UnigridsCalendar.gregorian().startOfDay(for: Date())
        var seen: Set<UnigridsID> = []
        return stops.compactMap { entry in
            guard let day = entry.stop.plannedDate, day <= horizon, day >= today,
                  let place = entry.place, seen.insert(place.id).inserted
            else { return nil }
            return place
        }
    }

    /// The trip's calendar and GPX, built when shared rather than on every redraw.
    private var exports: (calendar: TripCalendarFile?, gpx: TripGPXFile?) {
        let calendar = UnigridsCalendar.gregorian()
        let events = stops.compactMap { $0.calendarEvent(calendar: calendar) }
        let waypoints = stops.compactMap(\.waypoint)
        let name = trip.name.isEmpty ? "Trip" : trip.name
        return (
            events.isEmpty ? nil
                : TripCalendarFile(name: name, identifier: trip.id.uuidString, events: events),
            waypoints.isEmpty ? nil : TripGPXFile(name: name, waypoints: waypoints)
        )
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
        let doomed = offsets.map { trip.orderedStops[$0] }
        let log = LogStore(context: context)
        for stop in doomed {
            let name = ResolvedStop(stop, store: store).title
            do {
                let change = try log.delete(stop: stop)
                undo?.offer(change, message: "\(name) taken off the trip", from: undoHost)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func deleteTrip() {
        do {
            let change = try LogStore(context: context).delete(trip: trip)
            undo?.offer(change, message: change.summary { store.place($0)?.name })
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct RouteKey: Hashable {
    let stops: [String]
    let attempt: Int
}

/// The band, the map and the figures at the top of a trip.
private struct TripHeader: View {
    @Environment(\.unigrid) private var style
    let trip: Trip
    let stops: [ResolvedStop]
    let legs: [DriveLeg]
    let roads: [[Coordinate]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader(trip.name.isEmpty ? "Untitled trip" : trip.name, kicker: kicker)
            if stops.contains(where: { $0.coordinate != nil }) {
                TripMap(stops: stops, roads: roads)
                    .frame(height: 280)
            }
            TripFigures(trip: trip, stops: stops, legs: legs)
                .padding(UnigridStyle.pageMargin)
        }
    }

    private var kicker: String {
        [trip.status(on: Date()).name, TripDates.range(trip)]
            .compactMap(\.self).joined(separator: " · ")
    }
}

/// The itinerary: each stop, the drive into it, its forecast and what it has posted.
private struct ItinerarySection: View {
    @Environment(\.unigrid) private var style
    @Environment(AlertsCenter.self) private var alerts: AlertsCenter?
    @Environment(\.referenceStore) private var store
    let stops: [ResolvedStop]
    let trip: Trip
    let driveTimes: DriveTimes
    let forecasts: Forecasts
    @Binding var reordering: Bool
    let onAdd: () -> Void
    let onDetails: (TripStop) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Section {
            if stops.isEmpty {
                Text(
                    "No stops yet. Add the parks, sights, trails and places to sleep you "
                        + "mean to see, in the order you mean to see them."
                )
                .font(UnigridStyle.proseSmall)
                .foregroundStyle(style.inkSecondary)
                .listRowBackground(Color.clear)
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, entry in
                VStack(alignment: .leading, spacing: 8) {
                    if index > 0 {
                        LegLine(
                            leg: driveTimes.leg(from: stops[index - 1], to: entry),
                            failed: driveTimes.hasFailed(from: stops[index - 1], to: entry),
                            straightLine: straightLine(from: stops[index - 1], to: entry),
                            sameSpot: stops[index - 1].routeKey == entry.routeKey,
                            onRetry: driveTimes.retry
                        )
                    }
                    StopRow(number: index + 1, entry: entry, trip: trip) {
                        onDetails(entry.stop)
                    }
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
            .onMove(perform: onMove)
            .onDelete(perform: onDelete)

            Button(action: onAdd) {
                Label("Add stops", symbol: .add)
            }
            .buttonStyle(BrochureButtonStyle(.secondary))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            if stops.count > 1 {
                ListNotes {
                    #if os(iOS)
                        Text("Reorder to change the route; swipe a stop to take it off the trip.")
                    #else
                        Text("Drag stops to change the route.")
                    #endif
                }
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                SectionHead("Itinerary", detail: "\(stops.count)")
                #if os(iOS)
                    if stops.count > 1 {
                        Button(reordering ? "Done" : "Reorder") { reordering.toggle() }
                            .font(UnigridStyle.dataLabel)
                            .textCase(.uppercase)
                    }
                #endif
            }
        }
    }

    private func straightLine(from: ResolvedStop, to: ResolvedStop) -> Double {
        guard let start = from.coordinate, let end = to.coordinate else { return 0 }
        return start.distance(to: end)
    }
}

/// The trip in figures: stops, states, days, and the driving or the straight line.
struct TripFigures: View {
    let trip: Trip
    let stops: [ResolvedStop]
    var legs: [DriveLeg] = []

    var body: some View {
        let points = stops.compactMap(\.coordinate)
        let distance = TripRoute.totalDistance(points)
        let states = Set(stops.compactMap(\.place).flatMap { $0.states.map(\.code) })
        let allRouted = stops.count > 1 && legs.count == stops.count - 1
        FigureGrid(minimum: 110, spacing: 14) {
            FigureBlock(value: "\(stops.count)", label: "Stops", compact: true)
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
        let calendar = UnigridsCalendar.gregorian()
        let count = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)
        ).day ?? 0
        return max(count + 1, 1)
    }
}
