import CoreGraphics
import SwiftUI
import UnigridsCore

// A place's pin with its site type's pictogram: the map's close-up pin, and the
// marker in the map key and wherever a list wants to show what kind of place it is.

/// A place's pin as the map draws it close up: a solid shape in its kind of place's
/// colour, a white pictogram reversed out of it and a white keyline round it — the map
/// key's entries, and the marker in any list where telling a battlefield from a seashore
/// at a glance helps.
///
/// Three cues, each read on its own: **colour and pictogram are the kind of place, shape
/// is who runs it.** A visited place carries a green tick; a planned one a dashed ring.
public struct SitePin: View {
    @Environment(\.unigrid) private var style
    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private let type: SiteType
    private let tier: PlaceTier
    private let status: PlaceMarker.Status

    /// `tier` sets the shape, and defaults to the type's own.
    public init(type: SiteType, tier: PlaceTier? = nil, status: PlaceMarker.Status = .none) {
        self.type = type
        self.tier = tier ?? type.tier
        self.status = status
    }

    /// A place's own pin: its type's pictogram in its own tier's shape.
    public init(place: Place, status: PlaceMarker.Status = .none) {
        self.init(type: place.siteType, tier: place.tier, status: status)
    }

    /// How far the dashed ring and the tick reach past the pin, which the pin's frame
    /// includes so neighbours never overlap it.
    public static let margin: CGFloat = 4

    public var body: some View {
        let shape = MarkerShape(tier: tier)
        let side = shape.pictogramSize * scale
        let keyline = 1.5 * scale
        ZStack {
            MarkerOutline(shape)
                .fill(Color(SiteInk.pictogram))
            MarkerOutline(shape)
                .fill(Color(type.ink.pin))
                .padding(keyline)
            Image(systemName: UnigridsSymbol.site(type))
                .font(.system(size: shape.glyphSize * scale, weight: .semibold))
                .foregroundStyle(Color(SiteInk.pictogram))
        }
        .frame(width: side, height: side)
        .overlay {
            if status == .planned {
                MarkerOutline(shape)
                    .stroke(style.ink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .padding(-3.5 * scale)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if status == .visited {
                VisitedTick(diameter: 11 * scale)
                    .offset(x: 3 * scale, y: 3 * scale)
            }
        }
        .padding(Self.margin * scale)
        .accessibilityHidden(true)
    }
}

/// The tick on a visited place's pin: a white check on a green disc, ringed in white.
public struct VisitedTick: View {
    private let diameter: CGFloat

    public init(diameter: CGFloat = 11) {
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle().fill(Color(SiteInk.pictogram))
            Circle().fill(Color(SiteInk.visitedTick)).padding(diameter * 0.11)
            TickMark()
                .stroke(
                    Color(SiteInk.pictogram),
                    style: StrokeStyle(
                        lineWidth: diameter * 0.14,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .padding(diameter * 0.3)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// A check mark drawn in its rect, shared by the pin's tick and the map's.
public struct TickMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        Path(Self.path(in: rect, flipped: false))
    }

    /// The tick as a `CGPath`. `flipped` for a layer whose y counts upward, as an
    /// unflipped AppKit view's does.
    public static func path(in rect: CGRect, flipped: Bool) -> CGPath {
        func point(_ across: CGFloat, _ down: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * across,
                y: flipped ? rect.maxY - rect.height * down : rect.minY + rect.height * down
            )
        }
        let path = CGMutablePath()
        path.move(to: point(0, 0.55))
        path.addLine(to: point(0.38, 0.92))
        path.addLine(to: point(1, 0.12))
        return path
    }
}
