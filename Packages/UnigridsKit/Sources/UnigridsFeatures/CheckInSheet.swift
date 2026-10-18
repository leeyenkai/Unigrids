import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Manual check-in (SPECIFICATION.md §9).
///
/// Nothing is logged without the user confirming it, which is what this sheet is: the
/// confirmation. It writes once, on Save.
public struct CheckInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store

    let place: Place

    @State private var date = Date()
    @State private var rating: Int?
    @State private var notes = ""
    @State private var selectedPOIs: Set<UnigridsID> = []
    @State private var error: String?

    public init(place: Place) {
        self.place = place
    }

    private var checkInTargets: [PointOfInterest] {
        store.pointsOfInterest(in: place.id)
            .filter(\.kind.isCheckInTarget)
            .sorted { ($0.rank, $0.name) < ($1.rank, $1.name) }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text(place.name)
                } footer: {
                    Text("A visit can be back-dated for a trip you took years ago.")
                }

                Section("Rating") {
                    RatingPicker(rating: $rating)
                }

                Section("Notes") {
                    TextField("What do you want to remember?", text: $notes, axis: .vertical)
                        .lineLimit(3 ... 8)
                }

                if !checkInTargets.isEmpty {
                    Section {
                        ForEach(checkInTargets) { poi in
                            Button {
                                toggle(poi.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(poi.name)
                                        Text(poi.kind.name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedPOIs.contains(poi.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(UnigridStyle.parkGreen)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(
                                selectedPOIs.contains(poi.id) ? [.isSelected] : []
                            )
                        }
                    } header: {
                        Text("Sights and visitor centres")
                    } footer: {
                        Text("Anything you tick becomes a check-in inside this visit.")
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
            .navigationTitle("Check in")
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

    private func toggle(_ id: UnigridsID) {
        if selectedPOIs.contains(id) {
            selectedPOIs.remove(id)
        } else {
            selectedPOIs.insert(id)
        }
    }

    private func save() {
        let log = LogStore(context: context)
        do {
            let visit = try log.checkIn(
                to: place.id,
                on: date,
                source: .manual,
                rating: rating,
                notes: notes
            )
            for poi in selectedPOIs {
                try log.checkIn(at: .pointOfInterest(poi), during: visit, on: date)
            }
            dismiss()
        } catch {
            self.error = "Could not save this visit: \(error.localizedDescription)"
        }
    }
}

struct RatingPicker: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1 ... 5, id: \.self) { value in
                Button {
                    rating = rating == value ? nil : value
                } label: {
                    Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle((rating ?? 0) >= value ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                .accessibilityAddTraits((rating ?? 0) >= value ? [.isSelected] : [])
            }
            Spacer()
            if rating != nil {
                Button("Clear") { rating = nil }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
