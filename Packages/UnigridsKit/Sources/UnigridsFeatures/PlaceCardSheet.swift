import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// The card a map pin opens: name, type, states, a few quick facts, visit status and the
/// actions (SPECIFICATION.md §5).
public struct PlaceCardSheet: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss

    let place: Place

    @Query private var visits: [Visit]
    @State private var showCheckIn = false
    @State private var showStamp = false
    @State private var guidePlace: Place?

    public init(place: Place) {
        self.place = place
    }

    private var placeVisits: [Visit] {
        visits.filter { $0.place == place.id }.sorted { $0.date > $1.date }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    quickFacts
                    actions
                    if !placeVisits.isEmpty {
                        visitHistory
                    }
                }
                .padding(20)
            }
            .navigationTitle(place.name)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $guidePlace) { place in
                ParkGuideScreen(place: place)
            }
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInSheet(place: place)
        }
        .sheet(isPresented: $showStamp) {
            StampSheet(place: place)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: PlaceStyle.symbol(for: place))
                    .foregroundStyle(PlaceStyle.tint(for: place, in: style))
                Text(place.designation)
                    .font(.subheadline.weight(.medium))
                if !placeVisits.isEmpty {
                    Text("Visited")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(style.accent.opacity(0.15), in: Capsule())
                }
            }
            Text(place.statesDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quickFacts: some View {
        let facts = place.facts
        if facts.isEmpty {
            // No invented figures: 59 of the 63 parks have none in the pilot seed, and an
            // absent figure is the honest rendering.
            Text("Details arrive with the next data release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 12
            ) {
                if let year = facts.establishedYear {
                    StatTile(value: String(year), label: "Established")
                }
                if let acres = facts.areaAcres {
                    StatTile(value: UnigridsFormat.area(acres: acres), label: "Area")
                }
                if let visits = facts.annualVisits {
                    StatTile(
                        value: UnigridsFormat.visitors(visits),
                        label: facts.annualVisitsYear.map { "Visits in \($0)" } ?? "Visits"
                    )
                }
                if let range = UnigridsFormat.elevationRange(
                    lowest: facts.lowestElevationMetres,
                    highest: facts.highestElevationMetres
                ) {
                    StatTile(value: range, label: "Elevation")
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if place.tier.hasGuide, store.guide(for: place.id) != nil {
                Button {
                    guidePlace = place
                } label: {
                    Label("Open guide", systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                Button {
                    showCheckIn = true
                } label: {
                    Label("Check in", systemImage: "mappin.and.ellipse")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    showStamp = true
                } label: {
                    Label { Text("Stamp") } icon: { StampIcon() }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    openInMaps()
                } label: {
                    Label("Directions", systemImage: "car")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if let url = place.officialURL {
                    Link(destination: url) {
                        Label("Official page", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            // 3D exploration and the brochure viewer are specified (§6, §7) and land in
            // later milestones; saying so beats an action that does nothing.
            Text("Explore in 3D and the official brochure arrive in a later release.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var visitHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your visits")
                .font(.headline)
            ForEach(placeVisits) { visit in
                HStack {
                    Text(visit.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline)
                    Spacer()
                    Text(visit.source.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func openInMaps() {
        let location = CLLocation(
            latitude: place.centre.latitude,
            longitude: place.centre.longitude
        )
        let item = MKMapItem(
            location: location,
            address: MKAddress(fullAddress: place.statesDescription, shortAddress: place.name)
        )
        item.name = place.name
        item.openInMaps()
    }
}
