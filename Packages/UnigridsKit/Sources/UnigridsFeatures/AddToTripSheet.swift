import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// "Add to trip" from a map card or a guide (SPECIFICATION.md §5, §10): pick a trip that
/// has not finished, or start a new one with this place as its first stop.
struct AddToTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    @Query(sort: \Trip.createdAt, order: .reverse) private var trips: [Trip]

    let place: Place

    @State private var newName = ""
    @State private var error: String?

    private var openTrips: [Trip] {
        trips.filter { $0.status != .done }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("A name, like Utah in April", text: $newName)
                        .font(UnigridStyle.rowTitle)
                        .onSubmit(createTrip)
                    Button("Start a trip with \(place.name)", action: createTrip)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Kicker("New trip")
                }

                if !openTrips.isEmpty {
                    Section {
                        ForEach(openTrips) { trip in
                            Button {
                                add(to: trip)
                            } label: {
                                TripChoiceRow(trip: trip, placeID: place.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Kicker("Your trips")
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(style.seal)
                    }
                }
            }
            .paperPage()
            .navigationTitle("Add to a trip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheetSize()
        .presentationDetents([.medium, .large])
    }

    private func createTrip() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            let log = LogStore(context: context)
            let trip = try log.createTrip(name: name)
            try log.addStop(place.id, to: trip)
            dismiss()
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
    }

    private func add(to trip: Trip) {
        do {
            try LogStore(context: context).addStop(place.id, to: trip)
            dismiss()
        } catch {
            self.error = "Could not save: \(error.localizedDescription)"
        }
    }
}

struct TripChoiceRow: View {
    @Environment(\.unigrid) private var style
    let trip: Trip
    let placeID: UnigridsID

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Text(detail)
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            Spacer()
            if trip.orderedStops.contains(where: { $0.place == placeID }) {
                Text("ON THIS TRIP")
                    .font(UnigridStyle.dataLabel)
                    .foregroundStyle(style.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        let count = trip.orderedStops.count
        var parts = ["\(count) stop\(count == 1 ? "" : "s")", trip.status.name]
        if let start = trip.startDate {
            parts.insert(start.formatted(.dateTime.day().month(.abbreviated).year()), at: 0)
        }
        return parts.joined(separator: " · ")
    }
}
