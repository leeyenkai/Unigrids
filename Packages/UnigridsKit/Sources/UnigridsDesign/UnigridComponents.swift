import SwiftUI
import UnigridsCore

/// The black title band a Unigrid brochure opens with: park name reversed out in white,
/// designation and states beneath (SPECIFICATION.md §6, panel 1).
public struct UnigridTitleBand: View {
    @Environment(\.unigrid) private var style

    private let name: String
    private let designation: String
    private let states: String

    public init(name: String, designation: String, states: String) {
        self.name = name
        self.designation = designation
        self.states = states
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(UnigridStyle.bandTitle())
                .foregroundStyle(style.bandInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(designation)  ·  \(states)".uppercased())
                .font(UnigridStyle.dataLabel)
                .tracking(1.2)
                .foregroundStyle(style.bandInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, UnigridStyle.panelPadding)
        .padding(.vertical, 22)
        .background(style.band)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(designation), \(states)")
    }
}

/// One panel on the guide's grid: a hairline-ruled heading over its content.
public struct UnigridPanel<Content: View>: View {
    @Environment(\.unigrid) private var style

    private let title: String?
    private let content: Content

    public init(title: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.uppercased())
                        .font(UnigridStyle.panelHeading)
                        .tracking(1.4)
                        .foregroundStyle(style.ink)
                    Rectangle()
                        .fill(style.ink)
                        .frame(height: 2)
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(UnigridStyle.panelPadding)
        // Panels sharing a row take the row's height, so the grid reads as one sheet
        // of equal panels, the way a printed brochure does, rather than ragged boxes.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(style.panel)
        .overlay {
            Rectangle()
                .stroke(style.rule, lineWidth: 1)
        }
    }
}

/// A label-and-value row, as the brochures set their data panels.
public struct UnigridDataRow: View {
    @Environment(\.unigrid) private var style

    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(UnigridStyle.dataLabel)
                .tracking(1)
                .foregroundStyle(style.inkSecondary)
            Text(value)
                .font(UnigridStyle.dataValue)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// A numbered item, used by the sights panel so the guide, the 3D view and the
/// fly-through all read in the same order.
public struct UnigridNumberedItem: View {
    @Environment(\.unigrid) private var style

    private let number: Int
    private let title: String
    private let detail: String?
    private let isSeen: Bool

    public init(number: Int, title: String, detail: String?, isSeen: Bool = false) {
        self.number = number
        self.title = title
        self.detail = detail
        self.isSeen = isSeen
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(UnigridStyle.dataLabel)
                .foregroundStyle(isSeen ? style.onAccent : style.bandInk)
                .frame(width: 22, height: 22)
                .background(isSeen ? style.accent : style.band)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(UnigridStyle.itemTitle)
                        .foregroundStyle(style.ink)
                    if isSeen {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(style.accent)
                            .accessibilityHidden(true)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(number). \(title). \(detail ?? "")\(isSeen ? " Seen." : "")"
        )
    }
}

/// A chronology row: year in the margin, event beside it (SPECIFICATION.md §6, panel 10).
public struct UnigridChronologyRow: View {
    @Environment(\.unigrid) private var style
    @Environment(\.dynamicTypeSize) private var typeSize

    private let entry: ChronologyEntry

    public init(entry: ChronologyEntry) {
        self.entry = entry
    }

    public var body: some View {
        // At accessibility sizes the year and the text stack, rather than squeezing the
        // event into a sliver of column.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))

        layout {
            Text(entry.year)
                .font(UnigridStyle.dataLabel)
                .foregroundStyle(style.inkSecondary)
                .frame(
                    width: typeSize.isAccessibilitySize ? nil : 84,
                    alignment: .leading
                )
            Text(entry.text)
                .font(UnigridStyle.prose)
                .foregroundStyle(style.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.year): \(entry.text)")
    }
}

/// A labelled placeholder for content that a later milestone brings.
///
/// AGENTS.md §10: a stub is fine when it is labelled, and an empty panel that pretends to
/// work is not. This is how the guide shows where the brochure map will go without
/// implying it is missing by accident.
public struct UnigridPendingPanel: View {
    @Environment(\.unigrid) private var style

    private let title: String
    private let explanation: String

    public init(title: String, explanation: String) {
        self.title = title
        self.explanation = explanation
    }

    public var body: some View {
        UnigridPanel(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(style.inkSecondary)
                Text(explanation)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 20)
        }
    }
}
