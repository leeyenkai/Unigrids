import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// "Add to trip" from a map card, a guide, a sight or a trail (SPECIFICATION.md §5, §10):
/// pick a trip that has not finished, or start a new one with this as its first stop.
struct AddToTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    let place: Place
    /// What inside the place is being added: the place itself, or a sight or trail in it.
    var target: StopTarget = .place
    /// The stop's own name, where it is not the place's.
    var stopName: String?

    @State private var newName = ""
    @State private var error: String?

    private var name: String {
        stopName ?? place.name
    }

    private var openTrips: [Trip] {
        let now = Date()
        return trips.filter { $0.status(on: now) != .done }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    var body: some View {
        SheetPage(
            "Add to trip",
            kicker: name,
            actions: .cancel { dismiss() },
            height: 560
        ) {
            List {
                if !openTrips.isEmpty {
                    Section {
                        ForEach(openTrips) { trip in
                            let isOn = trip.orderedStops.contains {
                                $0.place == place.id && $0.target == target
                            }
                            Button {
                                add(to: trip)
                            } label: {
                                TripChoiceRow(trip: trip, isOn: isOn)
                            }
                            .buttonStyle(.plain)
                            .disabled(isOn)
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        SectionHead("Your trips", detail: "\(openTrips.count)")
                    }
                }

                Section {
                    TextField("A name, like Utah in April", text: $newName)
                        .font(UnigridStyle.rowTitle)
                        .onSubmit(createTrip)
                        .listRowBackground(Color.clear)
                    Button(action: createTrip) {
                        Label("New trip with \(name)", symbol: .add)
                    }
                    .buttonStyle(BrochureButtonStyle(openTrips.isEmpty ? .primary : .secondary))
                    .disabled(cleanedName.isEmpty)
                    .listRowBackground(Color.clear)
                } header: {
                    SectionHead("New trip")
                }

                if let error {
                    Section { ErrorLine(error).listRowBackground(Color.clear) }
                }
            }
            .listStyle(.plain)
        }
    }

    private var cleanedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createTrip() {
        guard !cleanedName.isEmpty else { return }
        do {
            let log = LogStore(context: context)
            let trip = try log.createTrip(name: cleanedName)
            try log.addStop(place.id, to: trip, target: target)
            undo?.notify("Started \(trip.name) with \(name)")
            dismiss()
        } catch {
            self.error = "That trip could not be saved: \(error.localizedDescription)"
        }
    }

    private func add(to trip: Trip) {
        do {
            try LogStore(context: context).addStop(place.id, to: trip, target: target)
            undo?.notify("Added to \(trip.name)")
            dismiss()
        } catch {
            self.error = "That stop could not be saved: \(error.localizedDescription)"
        }
    }
}

/// A trip to add to: its name, dates and size, and whether this is on it already.
struct TripChoiceRow: View {
    @Environment(\.unigrid) private var style
    let trip: Trip
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            TwoLineRow(title: trip.name, detail: detail)
            Spacer()
            if isOn {
                Text("ON THIS TRIP")
                    .font(UnigridStyle.dataLabel)
                    .foregroundStyle(style.accent)
            } else {
                Image(.add)
                    .foregroundStyle(style.ink)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        let count = trip.orderedStops.count
        var parts = ["\(count) stop\(count == 1 ? "" : "s")", trip.status(on: Date()).name]
        if let range = TripDates.range(trip) {
            parts.insert(range, at: 0)
        }
        return parts.joined(separator: " · ")
    }
}
