import SwiftUI

/// Actions in a row that carries on onto the next line when the row runs out of room,
/// rather than squeezing its labels — at large type sizes and on a narrow card alike.
public struct WrappingRow: Layout {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = Self.rows(subviews, width: width, spacing: spacing)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(widest, width), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var top = bounds.minY
        for row in Self.rows(subviews, width: bounds.width, spacing: spacing) {
            var left = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(
                    at: CGPoint(x: left, y: top + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                left += size.width + spacing
            }
            top += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// The subviews in rows: each at its ideal size, or the width available if wider.
    private static func rows(_ subviews: Subviews, width: CGFloat, spacing: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            row.sizes.append(size)
        }
        if !row.indices.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

/// Two actions side by side, stacked when the reader's type size would squeeze them.
public struct TwoUpRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout { content }
    }
}

/// Notes under a plain list's rows, set on the page's own paper. A plain list draws a
/// section footer on the system background — a black strip on every palette — so the
/// notes go in as the section's last row instead.
public struct ListNotes<Content: View>: View {
    @Environment(\.unigrid) private var style
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content
        }
        .font(UnigridStyle.caption)
        .foregroundStyle(style.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}
