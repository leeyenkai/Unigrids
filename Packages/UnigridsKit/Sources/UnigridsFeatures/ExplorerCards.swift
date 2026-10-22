import MapKit
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

// The 3D explorer's cards and controls: a sight's card, a facility's, a trail's, the
// fly-through bar and the strip of sights (SPECIFICATION.md §7).

/// A sight's card: its photograph, number, note, and what to do there — check in, look
/// around at street level where Apple has imagery, move on.
struct SightCard: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let sight: PointOfInterest
    let number: Int
    let count: Int
    let onCheckIn: () -> Void
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    let onClose: () -> Void

    @State private var scene: MKLookAroundScene?
    @State private var showLookAround = false
    @State private var addingToTrip = false

    var body: some View {
        ExplorerCardFrame(
            kicker: "Sight \(number) of \(count)",
            title: sight.name,
            onClose: onClose
        ) {
            HStack(alignment: .top, spacing: 12) {
                if let image = sight.image {
                    PlacePhoto(image: image, aspectRatio: 4 / 3, maxPoints: 240)
                        .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let summary = sight.summary {
                        Text(summary)
                            .font(UnigridStyle.proseSmall)
                            .foregroundStyle(style.ink)
                            .lineLimit(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let image = sight.image {
                        PhotoCredit(image: image)
                    }
                }
            }
            WrappingRow {
                Button(action: onCheckIn) {
                    Label("Check in", symbol: .checkIn)
                }
                Button { addingToTrip = true } label: {
                    Label("Add to trip", symbol: .addToTrip)
                }
                if scene != nil {
                    Button { showLookAround = true } label: {
                        Label("Look Around", symbol: .lookAround)
                    }
                }
                if let onPrevious {
                    Button(action: onPrevious) {
                        Label("Previous sight", symbol: .previous)
                    }
                    .labelStyle(.iconOnly)
                }
                if let onNext {
                    Button(action: onNext) {
                        Label("Next sight", symbol: .next)
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
        }
        .task(id: sight.id) {
            scene = try? await MKLookAroundSceneRequest(coordinate: sight.location.clCoordinate)
                .scene
        }
        .unigridsSheet(isPresented: $showLookAround) {
            LookAroundSheet(title: sight.name, scene: scene)
        }
        .unigridsSheet(isPresented: $addingToTrip) {
            if let place = store.place(sight.placeID) {
                AddToTripSheet(
                    place: place,
                    target: .pointOfInterest(sight.id),
                    stopName: sight.name
                )
            }
        }
    }
}

/// Street-level imagery of a sight, where Apple has it.
struct LookAroundSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let scene: MKLookAroundScene?

    var body: some View {
        SheetPage(
            title,
            kicker: "Look Around",
            actions: .done { dismiss() },
            width: 900,
            height: 620
        ) {
            LookAroundPreview(initialScene: scene, allowsNavigation: true, showsRoadLabels: true)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// A visitor centre's or campground's card.
struct FacilityCard: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let poi: PointOfInterest
    let onCheckIn: () -> Void
    let onClose: () -> Void
    @State private var addingToTrip = false

    var body: some View {
        ExplorerCardFrame(kicker: poi.kind.name, title: poi.name, onClose: onClose) {
            if let summary = poi.summary {
                Text(summary)
                    .font(UnigridStyle.proseSmall)
                    .foregroundStyle(style.ink)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hours = poi.hours {
                UnigridDataRow(label: "Hours", value: hours)
            }
            if poi.hasStamp {
                Label { Text("Passport stamp here") } icon: { StampIcon() }
                    .font(UnigridStyle.rowDetail)
            }
            WrappingRow {
                Button(action: onCheckIn) {
                    Label("Check in", symbol: .checkIn)
                }
                Button { addingToTrip = true } label: {
                    Label("Add to trip", symbol: .addToTrip)
                }
                if let url = poi.url {
                    Link(destination: url) {
                        Label("Website", symbol: .website)
                    }
                }
            }
            .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
        }
        .unigridsSheet(isPresented: $addingToTrip) {
            if let place = store.place(poi.placeID) {
                AddToTripSheet(place: place, target: .pointOfInterest(poi.id), stopName: poi.name)
            }
        }
    }
}

/// A trail's card in the explorer: figures, profile, the sights along it.
struct ExplorerTrailCard: View {
    let trail: Trail
    let sights: [PointOfInterest]
    let onClose: () -> Void

    private var passes: [String] {
        trail.sightIDs.compactMap { id in sights.first { $0.id == id }?.name }
    }

    var body: some View {
        ExplorerCardFrame(
            kicker: trail.estimatedDifficulty.map { "\($0.name), est." } ?? "Trail",
            title: trail.name,
            onClose: onClose
        ) {
            TrailFigures(trail: trail)
            TrailProfileChart(trail: trail, height: 80, showsAxes: false)
            if !passes.isEmpty {
                UnigridDataRow(
                    label: "Passes",
                    value: ListFormatter.localizedString(byJoining: passes)
                )
            }
            TrailActions(trail: trail)
        }
    }
}

/// The frame every explorer card shares: a band head, a close box, a panel beneath.
struct ExplorerCardFrame<Content: View>: View {
    @Environment(\.unigrid) private var style
    let kicker: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(kicker, onBand: true)
                    Text(title)
                        .font(UnigridStyle.bandTitle(20))
                        .foregroundStyle(style.bandInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(style.bandInk)
                        .frame(width: 28, height: 28)
                        .overlay { Rectangle().strokeBorder(style.bandInkSecondary, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(14)
            .background(style.band)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.panel)
        }
        .frame(maxWidth: 560)
        .overlay { Rectangle().strokeBorder(style.ink.opacity(0.4), lineWidth: 1) }
        .padding(12)
    }
}

/// The fly-through's controls: where it is, and back, pause, on, stop.
struct TourBar: View {
    @Environment(\.unigrid) private var style
    let progress: TourProgress
    let sight: PointOfInterest?
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SightNumber(number: progress.index + 1, isSelected: true)
            VStack(alignment: .leading, spacing: 1) {
                Kicker("Fly-through · \(progress.index + 1) of \(progress.count)", onBand: true)
                Text(sight?.name ?? "")
                    .font(UnigridStyle.action)
                    .foregroundStyle(style.bandInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                Button(action: onPrevious) { Image(systemName: "backward.fill") }
                    .disabled(progress.index == 0)
                    .accessibilityLabel("Previous sight")
                if progress.isPaused {
                    Button(action: onResume) { Image(systemName: "play.fill") }
                        .accessibilityLabel("Resume")
                } else {
                    Button(action: onPause) { Image(systemName: "pause.fill") }
                        .accessibilityLabel("Pause")
                }
                Button(action: onNext) { Image(systemName: "forward.fill") }
                    .disabled(progress.index + 1 >= progress.count)
                    .accessibilityLabel("Next sight")
                Button(action: onStop) { Image(systemName: "xmark") }
                    .accessibilityLabel("End fly-through")
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(style.bandInk)
            .frame(width: 34, height: 34)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(style.band)
    }
}

/// The sights along the bottom of the explorer on a narrow screen, numbered as in the
/// guide.
struct SightStrip: View {
    @Environment(\.unigrid) private var style
    let sights: [PointOfInterest]
    let current: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(sights.enumerated()), id: \.element.id) { index, sight in
                    Button {
                        onSelect(index)
                    } label: {
                        HStack(spacing: 8) {
                            SightNumber(number: index + 1, isSelected: index == current)
                            Text(sight.name)
                                .font(UnigridStyle.action)
                                .foregroundStyle(style.bandInk)
                                .lineLimit(1)
                        }
                        .padding(.trailing, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(style.band)
    }
}
