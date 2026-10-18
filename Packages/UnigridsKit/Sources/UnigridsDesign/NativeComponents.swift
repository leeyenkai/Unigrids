import SwiftUI
import UnigridsCore

// The native half of the design language (SPECIFICATION.md §14): the map, trips,
// passport, stats and settings use the current Apple design, so these components lean on
// semantic colours and system fonts rather than the Unigrid palette.

/// How a place is drawn on the map: colour by agency, symbol by kind.
public enum PlaceStyle {
    public static func tint(for place: Place) -> Color {
        switch place.agency {
        case .nps: place.tier == .nationalPark ? UnigridStyle.parkGreen : Color(hex: "4A7C59")
        case .forestService: Color(hex: "2F6B3A")
        case .blm: Color(hex: "8A6A2F")
        case .fishAndWildlife: Color(hex: "2B6A7A")
        case .stateAgency: Color(hex: "5C6BA8")
        case .other: Color(hex: "6E6E73")
        }
    }

    public static func symbol(for place: Place) -> String {
        switch place.kind {
        case .nationalPark: "tree.fill"
        case .npsUnit: "building.columns.fill"
        case .statePark: "leaf.fill"
        case .nationalForest, .nationalGrassland: "tree"
        case .blmMonument, .blmConservationArea: "mountain.2.fill"
        case .wildlifeRefuge: "bird.fill"
        case .naturalLandmark: "sparkles"
        case .scenicByway: "road.lanes"
        }
    }
}

/// A completion ring with its figure in the middle, for the stats page.
public struct CompletionRing: View {
    private let completion: Completion
    private let caption: String
    private let diameter: CGFloat

    public init(completion: Completion, caption: String, diameter: CGFloat = 132) {
        self.completion = completion
        self.caption = caption
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: diameter * 0.09)
            Circle()
                .trim(from: 0, to: completion.fraction)
                .stroke(
                    UnigridStyle.parkGreen,
                    style: StrokeStyle(lineWidth: diameter * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(completion.visited)")
                    .font(.system(size: diameter * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of \(completion.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(completion.description)")
        .accessibilityValue("\(Int((completion.fraction * 100).rounded())) percent")
    }
}

/// A headline figure with a label, the unit the stats pages are built from.
public struct StatTile: View {
    private let value: String
    private let label: String
    private let systemImage: String?

    public init(value: String, label: String, systemImage: String? = nil) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// The badge on a map pin or list row showing the user has been there.
public struct VisitStatusBadge: View {
    public enum Status {
        case visited
        case planned
        case none
    }

    private let status: Status

    public init(status: Status) {
        self.status = status
    }

    public var body: some View {
        switch status {
        case .visited:
            Label("Visited", systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(UnigridStyle.parkGreen)
                .accessibilityLabel("Visited")
        case .planned:
            Label("Planned", systemImage: "circle.dashed")
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Planned")
        case .none:
            EmptyView()
        }
    }
}

/// The non-affiliation line, which the specification requires in onboarding and About
/// (§14, §15). Centralised so it reads identically wherever it appears.
public struct NonAffiliationNotice: View {
    public init() {}

    public var body: some View {
        Text(
            "Unigrids is not affiliated with, endorsed by or sponsored by the "
                + "National Park Service or any other government agency."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
