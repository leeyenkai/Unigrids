import CoreGraphics
import SwiftUI
import UnigridsCore

// The pieces every screen is built from, so the map, the directory, the passport and the
// stats read as one publication rather than as a guide bolted onto a stock app
// (docs/design-system.md §2). Three rules hold them together:
//
//  1. The band. Every screen title is reversed out of a black band, as on a brochure.
//  2. Square geometry. Panels, tiles, buttons and markers have square corners; a hairline
//     rule separates, a heavy rule heads. System controls keep their own shapes.
//  3. Type over decoration. Helvetica Neue sets names and figures, a serif sets prose,
//     tracked capitals label. Icons are the exception, not the texture.

// MARK: - Type for native screens

extension UnigridStyle {
    /// A row's title in a list: a park's name.
    public static var rowTitle: Font {
        .custom("HelveticaNeue-Medium", size: 17, relativeTo: .body)
    }

    /// A row's second line.
    public static var rowDetail: Font {
        .custom("HelveticaNeue", size: 13, relativeTo: .footnote)
    }

    /// A headline figure: "23", "4.1 million".
    public static var figure: Font {
        .custom("HelveticaNeue-Bold", size: 30, relativeTo: .title)
    }

    /// A smaller figure, beside a label.
    public static var figureSmall: Font {
        .custom("HelveticaNeue-Bold", size: 20, relativeTo: .title3)
    }

    /// Button labels.
    public static var action: Font {
        .custom("HelveticaNeue-Medium", size: 15, relativeTo: .subheadline)
    }

    /// Longer passages outside a guide: a place's overview on the map card.
    public static var proseSmall: Font {
        .system(.callout, design: .serif)
    }
}

// MARK: - The band

/// A screen's title, reversed out of the black band (docs/design-system.md §2, rule 1).
///
/// The guide's `UnigridTitleBand` is this band at its fullest; every other screen opens
/// with the same band at screen-title size, so a reader moving from the map into a guide
/// is moving within one publication.
public struct BandHeader<Trailing: View>: View {
    @Environment(\.unigrid) private var style

    private let title: String
    private let kicker: String?
    private let compact: Bool
    private let trailing: Trailing

    /// `compact` sets the title smaller and the band tighter, for a sheet or a card, where
    /// the band names the task rather than the screen.
    public init(
        _ title: String,
        kicker: String? = nil,
        compact: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.kicker = kicker
        self.compact = compact
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(UnigridStyle.bandTitle(compact ? 22 : 30))
                    .foregroundStyle(style.bandInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let kicker {
                    Text(kicker.uppercased())
                        .font(UnigridStyle.dataLabel)
                        .tracking(1.2)
                        .foregroundStyle(style.bandInkSecondary)
                }
            }
            Spacer(minLength: 0)
            trailing
                .foregroundStyle(style.bandInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UnigridStyle.pageMargin)
        .padding(.top, compact ? 12 : 18)
        .padding(.bottom, compact ? 10 : 14)
        .background(style.band)
    }
}

/// Close, as a square ruled in the band's ink: the way out of a card that sits on a map.
public struct BandCloseButton: View {
    @Environment(\.unigrid) private var style
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 30
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(.dismiss)
                .font(.footnote.weight(.bold))
                .foregroundStyle(style.bandInk)
                .frame(width: side, height: side)
                .overlay { Rectangle().strokeBorder(style.bandInkSecondary, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

extension BandHeader where Trailing == EmptyView {
    public init(_ title: String, kicker: String? = nil, compact: Bool = false) {
        self.init(title, kicker: kicker, compact: compact) { EmptyView() }
    }
}

// MARK: - Rules and labels

/// A section's heading on a native page: tracked capitals over a heavy rule, as a guide
/// panel is headed.
public struct SectionHead: View {
    @Environment(\.unigrid) private var style

    private let title: String
    private let detail: String?

    public init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(UnigridStyle.panelHeading)
                    .tracking(1.4)
                    .foregroundStyle(style.ink)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(UnigridStyle.dataLabel)
                        .foregroundStyle(style.inkSecondary)
                        .monospacedDigit()
                }
            }
            Rectangle()
                .fill(style.ink)
                .frame(height: 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A hairline, the separator the brochures use between items.
public struct Hairline: View {
    @Environment(\.unigrid) private var style

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(style.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A small tracked-capitals label: "ESTABLISHED", "NATIONAL PARK · UTAH".
public struct Kicker: View {
    @Environment(\.unigrid) private var style

    private let text: String
    private let onBand: Bool

    public init(_ text: String, onBand: Bool = false) {
        self.text = text
        self.onBand = onBand
    }

    public var body: some View {
        Text(text.uppercased())
            .font(UnigridStyle.dataLabel)
            .tracking(1.1)
            .foregroundStyle(onBand ? style.bandInkSecondary : style.inkSecondary)
    }
}

// MARK: - Figures

/// A headline figure over its label, ruled above — the unit the stats and the map card
/// are built from. Square, and without a fill: the rule does the grouping.
public struct FigureBlock: View {
    @Environment(\.unigrid) private var style

    private let value: String
    private let label: String
    private let compact: Bool

    public init(value: String, label: String, compact: Bool = false) {
        self.value = value
        self.label = label
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Rectangle()
                .fill(style.ink)
                .frame(height: 1)
                .padding(.bottom, 4)
            Text(value)
                .font(compact ? UnigridStyle.figureSmall : UnigridStyle.figure)
                .foregroundStyle(style.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(UnigridStyle.dataLabel)
                .tracking(1)
                .foregroundStyle(style.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Buttons

/// Square-cornered buttons in the palette's ink: a solid one for the screen's main action
/// and a ruled one for the rest. Native button shapes are rounded; these are what makes an
/// action on a park card look like part of the brochure.
public struct BrochureButtonStyle: ButtonStyle {
    public enum Weight: Sendable {
        case primary
        case secondary
        /// Reversed out of a band.
        case onBand
    }

    @Environment(\.unigrid) private var style
    @Environment(\.isEnabled) private var isEnabled

    private let weight: Weight
    private let fullWidth: Bool

    public init(_ weight: Weight = .secondary, fullWidth: Bool = true) {
        self.weight = weight
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(UnigridStyle.action)
            .labelStyle(BrochureLabelStyle())
            // Two lines rather than smaller type: a label that shrinks to fit is a label
            // the reader who chose large type can no longer read.
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(background)
            .overlay {
                if weight == .secondary {
                    Rectangle().strokeBorder(style.ink, lineWidth: 1.2)
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : (isEnabled ? 1 : 0.4))
    }

    private var foreground: Color {
        switch weight {
        case .primary: style.page
        case .secondary: style.ink
        case .onBand: style.band
        }
    }

    private var background: Color {
        switch weight {
        case .primary: style.ink
        case .secondary: .clear
        case .onBand: style.bandInk
        }
    }
}

/// Icon and title close together, icon small, as the brochures set a pictogram beside text.
public struct BrochureLabelStyle: LabelStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Markers

/// The shape a place takes on the map and everywhere it is listed, by tier: who runs the
/// place. Colour and pictogram say what kind of place it is (`SiteInk`, `SitePin`); the
/// shape stays as the second cue, so the map still reads for anyone who cannot tell two
/// of the colours apart.
public enum MarkerShape: CaseIterable, Sendable {
    /// National parks.
    case square
    /// Other NPS units: a smaller square, the same family.
    case smallSquare
    /// State parks.
    case circle
    /// Other public land — forests, refuges, BLM land — and landmarks and byways. A
    /// hexagon rather than the diamond it replaced: a diamond's middle is too small to
    /// hold a pictogram, and a diamond reads as a road warning sign.
    case hexagon

    public init(tier: PlaceTier) {
        switch tier {
        case .nationalPark: self = .square
        case .npsUnit: self = .smallSquare
        case .statePark: self = .circle
        case .federalSite: self = .hexagon
        }
    }

    /// The side of a plain marker, without a pictogram: in lists, and on the map before
    /// it is close enough for pictograms.
    public var size: CGFloat {
        switch self {
        case .square: 14
        case .smallSquare: 10
        case .circle: 11
        case .hexagon: 12
        }
    }

    /// The side of a pin that carries its site type's pictogram.
    public var pictogramSize: CGFloat {
        switch self {
        case .square: 26
        case .smallSquare: 22
        case .circle: 23
        case .hexagon: 25
        }
    }

    /// The pictogram's point size inside a pin of `pictogramSize`: about half the side,
    /// which is what lets a battlefield's flags read as flags.
    public var glyphSize: CGFloat {
        switch self {
        case .square: 14
        case .smallSquare: 12
        case .circle: 12
        case .hexagon: 12
        }
    }

    public func path(in rect: CGRect) -> CGPath {
        switch self {
        case .square, .smallSquare:
            return CGPath(rect: rect, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .hexagon:
            // Point up, regular: as wide as √3/2 of its height, centred in the rect.
            let height = rect.height
            let width = min(rect.width, height * 0.866)
            let left = rect.midX - width / 2
            let right = rect.midX + width / 2
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: right, y: rect.minY + height / 4))
            path.addLine(to: CGPoint(x: right, y: rect.maxY - height / 4))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: left, y: rect.maxY - height / 4))
            path.addLine(to: CGPoint(x: left, y: rect.minY + height / 4))
            path.closeSubpath()
            return path
        }
    }
}

/// `MarkerShape` as a SwiftUI shape.
public struct MarkerOutline: Shape {
    private let shape: MarkerShape

    public init(_ shape: MarkerShape) {
        self.shape = shape
    }

    public func path(in rect: CGRect) -> Path {
        Path(shape.path(in: rect))
    }
}

/// A place's marker as it appears in lists and the legend: the same shape and ink as its
/// map pin, filled when visited, dashed when planned.
public struct PlaceMarker: View {
    public enum Status: Sendable {
        case visited
        case planned
        case none
    }

    @Environment(\.unigrid) private var style
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 14

    private let shape: MarkerShape
    private let tint: Color
    private let status: Status

    public init(tier: PlaceTier, tint: Color, status: Status = .none) {
        shape = MarkerShape(tier: tier)
        self.tint = tint
        self.status = status
    }

    public var body: some View {
        let scale = shape.size / MarkerShape.square.size
        ZStack {
            MarkerOutline(shape)
                .fill(status == .visited ? tint : Color.clear)
            MarkerOutline(shape)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 2, dash: status == .planned ? [3, 2] : [])
                )
        }
        .frame(width: side * max(scale, 0.75), height: side * max(scale, 0.75))
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

// MARK: - Pages

extension View {
    /// The paper a native screen is printed on: the palette's page, behind everything,
    /// with a list's own grey background turned off so it does not show through.
    public func paperPage() -> some View {
        modifier(PaperPage())
    }
}

extension View {
    /// A sheet's size on the Mac. macOS sizes a sheet to its content, and a `List` or
    /// `ScrollView` has no content size of its own, so a sheet built on one collapses to
    /// a sliver. iOS sizes sheets itself and ignores this.
    public func sheetSize(width: CGFloat = 480, height: CGFloat = 620) -> some View {
        #if os(macOS)
            frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
            self
        #endif
    }
}

private struct PaperPage: ViewModifier {
    @Environment(\.unigrid) private var style

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(style.page)
    }
}
