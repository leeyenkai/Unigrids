import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The first thing a new reader sees: three brochure panels saying what Unigrids is, and
/// the non-affiliation line SPECIFICATION.md §14 requires in onboarding.
struct OnboardingView: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            BandHeader("Unigrids", kicker: "A field guide to America's public lands")
            #if os(iOS)
                TabView(selection: $page) {
                    ForEach(0 ..< Self.pageCount, id: \.self) { index in
                        panel(index).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            #else
                // A paged TabView on macOS draws a tab strip, which no brochure has. The Mac
                // turns pages with the buttons instead.
                panel(page)
                    .id(page)
                    .transition(.push(from: .trailing))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

            HStack(spacing: 12) {
                PageSquares(count: Self.pageCount, current: page)
                Spacer()
                if page > 0 {
                    Button("Back") {
                        withAnimation { page -= 1 }
                    }
                    .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
                }
                Button(page < Self.pageCount - 1 ? "Next" : "Start exploring") {
                    if page < Self.pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                }
                .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                .keyboardShortcut(.defaultAction)
            }
            .padding(UnigridStyle.pageMargin)
        }
        .background(style.page)
        .interactiveDismissDisabled()
    }

    private static let pageCount = 3

    @ViewBuilder
    private func panel(_ index: Int) -> some View {
        switch index {
        case 0:
            OnboardingPanel(
                number: 1,
                title: "Every park on one map",
                text: "All 63 national parks, \(nps) more National Park Service sites, "
                    + "and a selection of state parks, monuments and wildlife refuges — "
                    + "each outlined on the map, each a tap away from its overview."
            ) {
                MarkerKeyArt()
            }
        case 1:
            OnboardingPanel(
                number: 2,
                title: "A guide for every national park",
                text: "Laid out like the brochures the Park Service has printed since 1977: "
                    + "the park's story, its sights in order, visitor centres, the practical "
                    + "details, a chronology — and the NPS's own photographs."
            ) {
                BandArt()
            }
        default:
            OnboardingPanel(
                number: 3,
                title: "A passport that fills itself",
                text: "Check in, stamp the passport, plan trips, and watch the squares fill. "
                    + "Your log lives on your devices and in your own iCloud. There are no "
                    + "accounts, no analytics and no servers."
            ) {
                NonAffiliationNotice()
            }
        }
    }

    private var nps: Int {
        store.places.count { $0.tier == .npsUnit }
    }
}

struct OnboardingPanel<Art: View>: View {
    @Environment(\.unigrid) private var style
    let number: Int
    let title: String
    let text: String
    @ViewBuilder let art: Art

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(number)")
                    .font(.custom("HelveticaNeue-Bold", size: 15))
                    .foregroundStyle(style.bandInk)
                    .frame(width: 30, height: 30)
                    .background(style.band)
                Text(title)
                    .font(UnigridStyle.bandTitle(34))
                    .foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(style.ink).frame(height: 2)
                Text(text)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(style.ink)
                    .fixedSize(horizontal: false, vertical: true)
                art
                    .padding(.top, 8)
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(UnigridStyle.pageMargin)
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The map's key, as a picture of what the map holds.
struct MarkerKeyArt: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PlaceTier.allCases, id: \.self) { tier in
                HStack(spacing: 12) {
                    PlaceMarker(
                        tier: tier,
                        tint: tint(tier),
                        status: tier == .nationalPark ? .visited : .none
                    )
                    Text(tier.name)
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func tint(_ tier: PlaceTier) -> Color {
        let agency: Agency = switch tier {
        case .nationalPark, .npsUnit: .nps
        case .statePark: .stateAgency
        case .federalSite: .blm
        }
        return Color(AgencyInk.forPlace(agency: agency, tier: tier).value(style.scheme))
    }
}

/// A miniature brochure: the band over a grid of panels.
struct BandArt: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(spacing: 6) {
            Text("Zion")
                .font(UnigridStyle.bandTitle(22))
                .foregroundStyle(style.bandInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(style.band)
            HStack(alignment: .top, spacing: 6) {
                ForEach(0 ..< 3, id: \.self) { column in
                    VStack(alignment: .leading, spacing: 4) {
                        Rectangle().fill(style.ink).frame(height: 2)
                        ForEach(0 ..< (column == 1 ? 6 : 4), id: \.self) { _ in
                            Rectangle().fill(style.rule).frame(height: 5)
                        }
                    }
                    .padding(8)
                    .background(style.panel)
                    .overlay { Rectangle().strokeBorder(style.rule, lineWidth: 1) }
                }
            }
        }
        .frame(maxWidth: 360)
        .accessibilityHidden(true)
    }
}

/// Which page of the onboarding is showing, as squares.
struct PageSquares: View {
    @Environment(\.unigrid) private var style
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< count, id: \.self) { index in
                Rectangle()
                    .fill(index == current ? style.ink : Color.clear)
                    .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1.2) }
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
