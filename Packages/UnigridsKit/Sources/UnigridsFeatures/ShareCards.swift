import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// Share cards (SPECIFICATION.md §11, "every stat card can become a share card"): a card
// rendered on the device when the reader asks for it, shown before it is sent, and handed
// to the system share sheet. Unigrids uploads nothing.

/// A button that opens the share sheet for a card.
struct ShareCardButton<Card: View>: View {
    let title: String
    var label = "Share"
    var weight = BrochureButtonStyle.Weight.secondary
    var compact = false
    @ViewBuilder let card: () -> Card

    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(label, symbol: .share)
        }
        .buttonStyle(BrochureButtonStyle(weight, fullWidth: !compact))
        .unigridsSheet(isPresented: $showing) {
            ShareCardSheet(title: title, card: card())
        }
    }
}

/// The card, rendered once as the sheet opens, with the share button beneath it.
struct ShareCardSheet<Card: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let title: String
    let card: Card

    @State private var image: CGImage?

    var body: some View {
        SheetPage(
            title,
            kicker: "Share card",
            actions: .done { dismiss() },
            width: 600,
            height: 780
        ) {
            ScrollView {
                VStack(spacing: 18) {
                    if let image {
                        let picture = Image(decorative: image, scale: 2)
                        picture
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 420)
                            .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                            .accessibilityLabel("The card to share")
                        ShareLink(item: picture, preview: SharePreview(title, image: picture)) {
                            Label("Share", symbol: .share)
                        }
                        .buttonStyle(BrochureButtonStyle(.primary))
                        .frame(maxWidth: 420)
                        Text(
                            "Made on this device. Unigrids sends it nowhere; you choose where."
                        )
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                        .multilineTextAlignment(.center)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .task { render() }
    }

    @MainActor
    private func render() {
        let content = card
            .frame(width: 540)
            .environment(\.unigrid, style)
            .environment(\.referenceStore, store)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        image = renderer.cgImage
    }
}

/// A card's page: the band with its title, the content on paper, and the app's name.
struct ShareCardFrame<Content: View>: View {
    @Environment(\.unigrid) private var style
    let title: String
    var kicker = "Unigrids"
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BandHeader(title, kicker: kicker)
            content()
                .padding(20)
        }
        .background(style.page)
    }
}

/// A Stats section with a Share beneath it that sends the section as a card.
struct ShareableSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
            HStack {
                Spacer()
                ShareCardButton(title: title, compact: true) {
                    ShareCardFrame(title: "My parks", kicker: "Unigrids · \(title)") {
                        content()
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

/// A visit as a card: the place, the day, its stamp if it has one, what was hiked, and the
/// weather that day.
struct VisitShareCard: View {
    @Environment(\.unigrid) private var style
    @Environment(\.referenceStore) private var store
    let visit: VisitCardData

    var body: some View {
        ShareCardFrame(title: visit.placeName, kicker: visit.kicker) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(visit.day)
                        .font(UnigridStyle.bandTitle(26))
                        .foregroundStyle(style.ink)
                    if let rating = visit.rating {
                        HStack(spacing: 2) {
                            ForEach(0 ..< rating, id: \.self) { _ in Image(.rated) }
                        }
                        .foregroundStyle(style.ink)
                    }
                    ForEach(visit.lines, id: \.self) { line in
                        Text(line)
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let face = visit.stamp {
                    StampView(face: face, diameter: 150)
                }
            }
        }
    }
}

/// What a visit card shows, read from the log while it is open.
struct VisitCardData {
    let placeName: String
    let kicker: String
    let day: String
    let rating: Int?
    let lines: [String]
    let stamp: StampFace?
}

/// A trip as a card: its name and dates, its figures, and its stops in order.
struct TripShareCard: View {
    @Environment(\.unigrid) private var style
    let name: String
    let dates: String?
    let stops: [(title: String, detail: String)]
    let figures: [(value: String, label: String)]

    var body: some View {
        ShareCardFrame(title: name, kicker: dates ?? "Unigrids") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(figures, id: \.label) { figure in
                        FigureBlock(value: figure.value, label: figure.label, compact: true)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(stops.prefix(14).enumerated()), id: \.offset) { index, stop in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            SightNumber(number: index + 1)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(stop.title)
                                    .font(UnigridStyle.rowTitle)
                                    .foregroundStyle(style.ink)
                                if !stop.detail.isEmpty {
                                    Text(stop.detail)
                                        .font(UnigridStyle.rowDetail)
                                        .foregroundStyle(style.inkSecondary)
                                }
                            }
                        }
                    }
                    if stops.count > 14 {
                        Text("and \(stops.count - 14) more stops")
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
            }
        }
    }
}
