import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The stamp sheet (SPECIFICATION.md §9).
///
/// Asks for the date and, where a site has more than one official cancellation location,
/// which one. Press and hold to stamp — the gesture is the point, and the haptic thump
/// and ink settle that follow it are what makes it feel like a stamp rather than a form.
public struct StampSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style

    let place: Place
    /// Defaults to today, or to the visit's date when stamping from a visit.
    private let suggestedDate: Date

    @State private var date: Date
    @State private var stampLocationID: UnigridsID?
    @State private var realStampCollected = false
    @State private var pressing = false
    @State private var stamped: Stamp?
    @State private var saving = false
    @State private var error: String?
    @State private var onSite = OnSiteCheck()

    public init(place: Place, suggestedDate: Date = Date()) {
        self.place = place
        self.suggestedDate = suggestedDate
        _date = State(initialValue: suggestedDate)
    }

    /// The sheet for one of a site's stamp locations, chosen from its passport slot.
    init(place: Place, location: UnigridsID?) {
        self.init(place: place)
        _stampLocationID = State(initialValue: location)
    }

    private var stampLocations: [PointOfInterest] {
        store.stampLocations(in: place.id)
    }

    private var region: PassportRegion {
        place.resolvedPassportRegion
    }

    private var previewFace: StampFace {
        StampFace(
            siteName: place.name,
            date: date,
            stateCode: place.states.first?.code ?? "US",
            region: region,
            // A fixed preview seed: the real impression gets its own when it is saved, so
            // the preview must not pretend to show the exact impression you will get.
            seed: 0xC0FF_EE00,
            isVerifiedOnSite: false
        )
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let stamped {
                        stampedResult(stamped)
                    } else {
                        preview
                        controls
                    }
                }
                .padding(24)
            }
            .navigationTitle(stamped == nil ? "Stamp" : "Stamped")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stamped == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .sheetSize(width: 520, height: 680)
    }

    private var preview: some View {
        VStack(spacing: 10) {
            StampView(face: previewFace, diameter: 150)
                .scaleEffect(pressing ? 0.88 : 1)
                .animation(.spring(duration: 0.25), value: pressing)
            Text("\(region.name) region")
                .font(.caption)
                .foregroundStyle(.secondary)
            if America250.applies(to: date) {
                Label(
                    "Dated in 2026 — this impression gets the America 250 seal",
                    systemImage: "seal"
                )
                .font(.caption)
                .foregroundStyle(style.seal)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            DatePicker("Date", selection: $date, displayedComponents: .date)

            if stampLocations.count > 1 {
                Picker("Stamp location", selection: $stampLocationID) {
                    Text("Not specified").tag(UnigridsID?.none)
                    ForEach(stampLocations) { location in
                        Text(location.name).tag(UnigridsID?.some(location.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle("I collected the paper cancellation too", isOn: $realStampCollected)
                .font(.subheadline)

            Button {
                // The button is here for anyone who cannot press and hold; the gesture
                // below is the intended way in.
                save()
            } label: {
                Label { Text("Stamp") } icon: { StampIcon(isFilled: true) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .onLongPressGesture(minimumDuration: 0.45) {
                save()
            } onPressingChanged: { isPressing in
                pressing = isPressing
            }

            Text("Press and hold to stamp.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func stampedResult(_ stamp: Stamp) -> some View {
        VStack(spacing: 16) {
            StampView(
                face: StampFace(
                    siteName: place.name,
                    date: stamp.date,
                    stateCode: place.states.first?.code ?? "US",
                    region: region,
                    seed: stamp.seed,
                    isVerifiedOnSite: stamp.isVerifiedOnSite
                ),
                diameter: 170
            )
            Text(
                stamp.isVerifiedOnSite
                    ? "Stamped on site. Added to your passport and your log."
                    : "Added to your passport and your log."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func save() {
        guard stamped == nil, !saving else { return }
        saving = true
        Task {
            // Only a stamp dated today can have been made on site, so only then is the
            // reader's location asked for (SPECIFICATION.md §9, §15).
            let verified = Calendar.current.isDateInToday(date)
                ? await onSite.isOnSite(at: place, boundary: store.boundary(for: place.id))
                : false
            let log = LogStore(context: context)
            do {
                let stamp = try log.stamp(
                    place.id,
                    at: stampLocationID,
                    on: date,
                    verifiedOnSite: verified,
                    realStampCollected: realStampCollected
                )
                #if os(iOS)
                    // The haptic thump §9 asks for.
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                #endif
                withAnimation(.spring(duration: 0.4)) { stamped = stamp }
            } catch {
                self.error = "Could not save this stamp: \(error.localizedDescription)"
            }
            saving = false
        }
    }
}

#if os(iOS)
    import UIKit
#endif
