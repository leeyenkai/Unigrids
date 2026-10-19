import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// MARK: - Editing

/// Create or edit a trip: name, dates, status and notes.
struct TripEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let trip: Trip?

    @State private var name = ""
    @State private var hasDates = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(4 * 86400)
    @State private var status = TripStatus.planned
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Utah in April", text: $name)
                }
                Section {
                    Toggle("Dates", isOn: $hasDates)
                    if hasDates {
                        DatePicker("Start", selection: $start, displayedComponents: .date)
                        DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                    }
                }
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(TripStatus.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }
                Section("Notes") {
                    TextField("Permits to book, who is coming", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(trip == nil ? "New trip" : "Edit trip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(trip == nil ? "Create" : "Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let trip else { return }
        name = trip.name
        hasDates = trip.startDate != nil
        start = trip.startDate ?? Date()
        end = trip.endDate ?? start
        status = trip.status
        notes = trip.notes
    }

    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        do {
            let log = LogStore(context: context)
            if let trip {
                try log.update {
                    trip.name = cleaned
                    trip.startDate = hasDates ? start : nil
                    trip.endDate = hasDates ? end : nil
                    trip.status = status
                    trip.notes = notes
                }
            } else {
                let created = try log.createTrip(
                    name: cleaned,
                    startDate: hasDates ? start : nil,
                    endDate: hasDates ? end : nil,
                    status: status
                )
                try log.update { created.notes = notes }
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Search every place and add it to the trip.
struct StopPicker: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    let trip: Trip

    @State private var query = ""

    private var results: [Place] {
        let onTrip = Set(trip.orderedStops.map(\.placeID))
        let matches = query.isEmpty ? store.nationalParks : store.search(query, limit: 60)
        return matches.filter { !onTrip.contains($0.id.rawValue) }
    }

    var body: some View {
        NavigationStack {
            List(results) { place in
                Button {
                    _ = try? LogStore(context: context).addStop(place.id, to: trip)
                    dismiss()
                } label: {
                    PlaceRow(place: place, status: .none)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .paperPage()
            .searchable(text: $query, prompt: "Parks, monuments, state parks")
            .navigationTitle("Add a stop")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheetSize()
    }
}
