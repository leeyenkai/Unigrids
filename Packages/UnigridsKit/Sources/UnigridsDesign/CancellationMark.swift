import SwiftUI

/// The passport cancellation, as a mark small enough to sit in a button.
///
/// There is no rubber-stamp symbol in SF Symbols — `stamp` and `stamp.fill` do not exist
/// in any version, which is why five call sites were drawing nothing at all. Rather than
/// settle for an approximate symbol, this is the same geometry `StampView` draws at full
/// size: two concentric rings crossed by two rules. The passport, the guide's Stamp action
/// and the place card finally show the same thing.
public struct CancellationMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = side / 2
        let inner = outer * 0.74
        let barHalfWidth = inner * 0.78
        let barOffset = inner * 0.34

        var path = Path()
        path.addEllipse(in: CGRect(
            x: centre.x - outer, y: centre.y - outer,
            width: outer * 2, height: outer * 2
        ))
        path.addEllipse(in: CGRect(
            x: centre.x - inner, y: centre.y - inner,
            width: inner * 2, height: inner * 2
        ))
        for offset in [-barOffset, barOffset] {
            path.move(to: CGPoint(x: centre.x - barHalfWidth, y: centre.y + offset))
            path.addLine(to: CGPoint(x: centre.x + barHalfWidth, y: centre.y + offset))
        }
        return path
    }
}

/// The cancellation mark sized and weighted like an SF Symbol beside it.
///
/// Scales with Dynamic Type through `@ScaledMetric`, so it does not stay a fixed dot while
/// the text beside it grows.
public struct StampIcon: View {
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 16

    private let isFilled: Bool

    public init(isFilled: Bool = false) {
        self.isFilled = isFilled
    }

    public var body: some View {
        CancellationMark()
            .stroke(style: StrokeStyle(lineWidth: isFilled ? side * 0.14 : side * 0.09))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
