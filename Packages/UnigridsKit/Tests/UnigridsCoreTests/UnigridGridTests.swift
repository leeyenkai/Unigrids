import Testing
@testable import UnigridsCore

@Suite("Unigrid grid metrics")
struct UnigridGridTests {
    @Test("the column count lands where the specification asks, per device")
    func perDeviceColumnCounts() {
        // iPhone portrait, 16pt gutters each side.
        #expect(UnigridGrid.columnCount(availableWidth: 390 - 32) == 1)
        // iPhone landscape — the "unfolded" two-panel view of §6.
        #expect(UnigridGrid.columnCount(availableWidth: 844 - 32) == 2)
        // iPad portrait.
        #expect(UnigridGrid.columnCount(availableWidth: 834 - 32) == 2)
        // iPad landscape.
        #expect(UnigridGrid.columnCount(availableWidth: 1194 - 32) == 3)
        // A wide Mac window, capped by the template.
        #expect(UnigridGrid.columnCount(availableWidth: 1800) == 4)
    }

    @Test("larger type takes columns away instead of shrinking text")
    func largerTypeCollapsesColumns() {
        // The rule from §14: the grid collapses rather than the type.
        let width = 1194.0
        #expect(UnigridGrid.columnCount(availableWidth: width, typeScale: 1.0) == 3)
        #expect(UnigridGrid.columnCount(availableWidth: width, typeScale: 1.4) == 2)
        #expect(UnigridGrid.columnCount(availableWidth: width, typeScale: 2.2) == 1)
    }

    @Test("column counts never fall below one, whatever the inputs")
    func neverFewerThanOneColumn() {
        #expect(UnigridGrid.columnCount(availableWidth: 10, typeScale: 5) == 1)
        #expect(UnigridGrid.columnCount(availableWidth: 0) == 1)
        #expect(UnigridGrid.columnCount(availableWidth: -100) == 1)
        #expect(UnigridGrid.columnCount(availableWidth: 400, maximumColumns: 0) == 1)
    }

    @Test("a type scale below the default does not shrink the minimum width")
    func smallTypeDoesNotWidenTheGrid() {
        // Someone on the smallest text size should not get five columns of tiny text.
        #expect(UnigridGrid.minimumColumnWidth(typeScale: 0.5) == UnigridGrid.baseColumnWidth)
    }

    @Test("a panel never spans more columns than the grid has")
    func spanIsClamped() {
        #expect(UnigridGrid.span(for: .story, in: 3) == 2)
        #expect(UnigridGrid.span(for: .story, in: 1) == 1)
        #expect(UnigridGrid.span(for: .chronology, in: 4) == 1)
    }
}

@Suite("Unigrid row packing")
struct UnigridRowTests {
    private let panels: [GuidePanel] = [
        .atAGlance, .story, .majorSights, .visitorCentres, .chronology,
    ]

    @Test("one column puts every panel on its own row")
    func singleColumn() {
        let rows = UnigridGrid.rows(panels: panels, columnCount: 1)
        #expect(rows.count == panels.count)
        #expect(rows.allSatisfy { $0.count == 1 })
    }

    @Test("a two-column panel takes a row of its own in a two-column grid")
    func wideePanelFillsTwoColumnRow() {
        let rows = UnigridGrid.rows(panels: [.atAGlance, .story, .majorSights], columnCount: 2)
        #expect(rows.map { $0.map(\.id) } == [
            ["at-a-glance"], ["story"], ["major-sights"],
        ])
    }

    @Test("panels pack in reading order, never reshuffled to fill a gap")
    func orderIsPreserved() {
        let rows = UnigridGrid.rows(panels: panels, columnCount: 3)
        let flattened = rows.flatMap { $0.map(\.id) }
        #expect(flattened == panels.map(\.id))
    }

    @Test("no row ever exceeds the column count")
    func rowsNeverOverflow() {
        for columns in 1 ... 4 {
            let rows = UnigridGrid.rows(panels: panels, columnCount: columns)
            for row in rows {
                let used = row.reduce(0) { $0 + UnigridGrid.span(for: $1, in: columns) }
                #expect(used <= columns, "row of \(used) in \(columns) columns")
            }
        }
    }

    @Test("no panels means no rows")
    func emptyInput() {
        #expect(UnigridGrid.rows(panels: [], columnCount: 3).isEmpty)
    }
}
