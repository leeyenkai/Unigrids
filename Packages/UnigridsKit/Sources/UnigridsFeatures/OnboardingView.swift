import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The first thing a new reader sees: four brochure panels saying what Unigrids is, and
/// the non-affiliation line SPECIFICATION.md §14 requires in onboarding. Skip leaves at
/// any page; Settings can show it again.
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
                if page < Self.pageCount - 1 {
                    Button("Skip", action: onFinish)
                        .buttonStyle(.plain)
                        .font(UnigridStyle.action)
                        .foregroundStyle(style.inkSecondary)
                        .keyboardShortcut(.cancelAction)
                }
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

    private static let pageCount = 4

    @ViewBuilder
    private func panel(_ index: Int) -> some View {
        switch index {
        case 0:
            OnboardingPanel(
                number: 1,
                title: "Every public land on one map",
                text: mapText
            ) {
                MarkerKeyArt()
            }
        case 1:
            OnboardingPanel(
                number: 2,
                title: "A guide for every national park",
                text: "Laid out like the brochures the Park Service has printed since 1977: "
                    + "the park's story, its sights in order, \(store.allTrails.count.formatted()) "
                    + "trails measured from the ground up, the official brochure, and every "
                    + "park in 3D with a guided fly-through."
            ) {
                BandArt()
            }
        case 2:
            OnboardingPanel(
                number: 3,
                title: "Plan the trip",
                text: "Put parks, sights, trails and places to sleep in order and see the "
                    + "drive between them, the forecast for each day, closures the NPS has "
                    + "posted and permits to book — with reminders when booking windows open."
            ) {
                PlannerArt()
            }
        default:
            OnboardingPanel(
                number: 4,
                title: "A passport that fills itself",
                text: "Check in, stamp the passport, log your hikes, import visits from your "
                    + "photos, and watch the squares fill. Your log is yours: it lives on your "
                    + "devices, syncs through your own iCloud where that is set up, and exports "
                    + "to a file from Settings. There are no accounts, no analytics and no servers."
            ) {
                NonAffiliationNotice()
            }
        }
    }

    private var mapText: String {
        let parks: Int = count(PlaceTier.nationalPark)
        let units: Int = count(PlaceTier.npsUnit)
        let forests: Int = count(SiteType.nationalForest)
        let refuges: Int = count(SiteType.wildlifeRefuge)
        let stateParks: String = count(SiteType.statePark).formatted()
        let lands = "All \(parks) national parks and \(units) more National Park Service sites, "
            + "\(forests) national forests, \(refuges) wildlife refuges, \(stateParks) state "
            + "parks, the BLM's monuments, National Natural Landmarks and scenic byways"
        return lands + " — each with its own pin, most outlined. Lay Interstates, US highways "
            + "and Amtrak over the top."
    }

    private func count(_ type: SiteType) -> Int {
        store.places.count { $0.siteType == type }
    }

    private func count(_ tier: PlaceTier) -> Int {
        store.places.count { $0.tier == tier }
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
                    .font(.custom("HelveticaNeue-Bold", size: 15, relativeTo: .subheadline))
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

/// The map's key, as a picture of what the map holds: a pin for each kind of place.
struct MarkerKeyArt: View {
    @Environment(\.unigrid) private var style

    private static let shown: [SiteType] = [
        .nationalPark, .nationalMonument, .historicSite, .battlefield, .seashore,
        .statePark, .nationalForest, .wildlifeRefuge, .naturalLandmark, .scenicByway,
    ]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            ForEach(Self.shown) { type in
                HStack(spacing: 10) {
                    SitePin(type: type, status: type == .nationalPark ? .visited : .none)
                    Text(type.name)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.ink)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A trip in miniature: three numbered stops joined by the road between them.
struct PlannerArt: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(
                Array(["Zion", "Bryce Canyon", "Capitol Reef"].enumerated()),
                id: \.offset
            ) { index, name in
                if index > 0 {
                    HStack(spacing: 10) {
                        Rectangle().fill(style.rule).frame(width: 2, height: 22).padding(
                            .leading,
                            10
                        )
                        Label(index == 1 ? "1 h 50 min" : "2 h 20 min", symbol: .drive)
                            .font(UnigridStyle.rowDetail)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                HStack(spacing: 10) {
                    SightNumber(number: index + 1)
                    Text(name)
                        .font(UnigridStyle.rowTitle)
                        .foregroundStyle(style.ink)
                }
            }
        }
        .accessibilityHidden(true)
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
