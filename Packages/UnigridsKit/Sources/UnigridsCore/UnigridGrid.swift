import Foundation

/// How many columns a Unigrid guide gets, and how wide they have to be.
///
/// This is the load-bearing accessibility rule in the whole app, so it lives here as a
/// pure function rather than inside a view: **the grid collapses to fewer columns rather
/// than shrinking text** (SPECIFICATION.md §14, AGENTS.md §6). Larger type raises the
/// minimum width a column needs, which takes columns away. Nothing scales down.
///
/// The widths are chosen so the layout lands where the specification asks (§6): one
/// column on iPhone, two or three on iPad, three or four on a Mac window.
public enum UnigridGrid {
    /// The narrowest a column may be at the default text size.
    ///
    /// A brochure panel is about 4 inches across; 320 points is the closest thing to that
    /// which also produces the per-device column counts §6 describes.
    public static let baseColumnWidth: Double = 320

    /// The largest number of columns the template uses, from the brochure's own module.
    public static let maximumColumns = 4

    /// The minimum column width at a given type scale.
    ///
    /// `typeScale` is 1 at the default text size and grows with the user's setting — the
    /// design layer maps `DynamicTypeSize` onto it, so this stays free of SwiftUI.
    public static func minimumColumnWidth(typeScale: Double) -> Double {
        baseColumnWidth * max(1, typeScale)
    }

    /// The number of columns to lay out.
    public static func columnCount(
        availableWidth: Double,
        typeScale: Double = 1,
        maximumColumns: Int = maximumColumns
    ) -> Int {
        guard availableWidth > 0, maximumColumns > 0 else { return 1 }
        let minimum = minimumColumnWidth(typeScale: typeScale)
        let fitting = Int((availableWidth / minimum).rounded(.down))
        return min(max(fitting, 1), maximumColumns)
    }

    /// How many columns a panel actually spans, never more than the grid has.
    public static func span(for panel: GuidePanel, in columnCount: Int) -> Int {
        min(panel.preferredColumnSpan, columnCount)
    }

    /// Pack panels into rows, respecting each panel's preferred span.
    ///
    /// Greedy and order-preserving: a panel goes on the current row if its span still
    /// fits, and starts a new row otherwise. Order matters more than density here — the
    /// template's sequence is the reading order, and a brochure does not reshuffle its
    /// panels to fill a gap.
    public static func rows(panels: [GuidePanel], columnCount: Int) -> [[GuidePanel]] {
        let columns = max(1, columnCount)
        var rows: [[GuidePanel]] = []
        var current: [GuidePanel] = []
        var used = 0

        for panel in panels {
            let width = span(for: panel, in: columns)
            if used + width > columns, !current.isEmpty {
                rows.append(current)
                current = []
                used = 0
            }
            current.append(panel)
            used += width
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
