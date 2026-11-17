import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// A passport book opened at a region, turned page by page like the paper one (§9): swipe
/// or the arrows for the next region, pinch in or Contents for every region at once. With
/// Reduce Motion the pages cross-fade instead of sliding.
struct PassportBookReader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let regions: [PassportRegion]
    @State var region: PassportRegion
    @State private var forward = true
    @State private var showsContents = false

    private var position: Int {
        regions.firstIndex(of: region) ?? 0
    }

    var body: some View {
        PassportRegionPage(region: region)
            .id(region)
            .transition(turn)
            .simultaneousGesture(
                DragGesture(minimumDistance: 40).onEnded { drag in
                    let across = drag.translation.width
                    guard abs(across) > 80, abs(across) > abs(drag.translation.height) * 2
                    else { return }
                    turnPage(by: across < 0 ? 1 : -1)
                }
            )
            .simultaneousGesture(
                MagnifyGesture().onEnded { pinch in
                    if pinch.magnification < 0.8 {
                        showsContents = true
                    }
                }
            )
            .toolbar {
                ToolbarItemGroup {
                    Button { turnPage(by: -1) } label: {
                        Label("Previous region", systemImage: "chevron.left")
                    }
                    .disabled(position == 0)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .help("Previous region")
                    Button { turnPage(by: 1) } label: {
                        Label("Next region", systemImage: "chevron.right")
                    }
                    .disabled(position == regions.count - 1)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .help("Next region")
                    Button { showsContents = true } label: {
                        Label("Contents", systemImage: "square.grid.2x2")
                    }
                    .help("Every region")
                }
            }
            .unigridsSheet(isPresented: $showsContents) {
                PassportContents(regions: regions, current: region) { chosen in
                    showsContents = false
                    forward = (regions.firstIndex(of: chosen) ?? 0) >= position
                    withAnimation(.easeInOut(duration: 0.3)) { region = chosen }
                }
            }
            .accessibilityAction(named: "Next region") { turnPage(by: 1) }
            .accessibilityAction(named: "Previous region") { turnPage(by: -1) }
    }

    private var turn: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading),
            removal: .move(edge: forward ? .leading : .trailing)
        )
    }

    private func turnPage(by step: Int) {
        let next = position + step
        guard regions.indices.contains(next) else { return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35)) {
            region = regions[next]
        }
    }
}

/// Every region's title page at once, to jump to one.
struct PassportContents: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.dismiss) private var dismiss
    @Query private var stamps: [Stamp]
    let regions: [PassportRegion]
    let current: PassportRegion
    let open: (PassportRegion) -> Void

    var body: some View {
        let stamped = Set(stamps.map(\.place))
        let byRegion = store.placesByPassportRegion()
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 16)],
                    spacing: 16
                ) {
                    ForEach(regions) { region in
                        let sites = (byRegion[region] ?? []).filter(\.isNationalParkSystemSite)
                        Button { open(region) } label: {
                            RegionTitleCard(
                                region: region,
                                completion: Completion(
                                    visited: sites.count { stamped.contains($0.id) },
                                    total: sites.count
                                ),
                                isCurrent: region == current
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(style.page)
            .navigationTitle("Contents")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// A region's title page in small: its ink, its name, its count.
private struct RegionTitleCard: View {
    @Environment(\.unigrid) private var style
    let region: PassportRegion
    let completion: Completion
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(style.band)
                .frame(height: 10)
            Rectangle()
                .fill(style.regionInk(region))
                .frame(height: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(region.name)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(completion.description)
                    .font(UnigridStyle.dataValue)
                    .monospacedDigit()
                    .foregroundStyle(style.ink)
                Text("\(region.country.passportSlotNoun) stamped")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(style.page)
        .overlay {
            Rectangle().strokeBorder(
                isCurrent ? style.ink : style.rule, lineWidth: isCurrent ? 2 : 1
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(region.name), \(completion.description) "
                + "\(region.country.passportSlotNoun) stamped"
        )
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }
}

/// The left page of a spread: how far the region has come, a square per site.
struct RegionTitleSummary: View {
    @Environment(\.unigrid) private var style
    let region: PassportRegion
    let sites: [Place]
    let stamped: Set<UnigridsID>
    let beyond: Int

    var body: some View {
        let ink = style.regionInk(region)
        let done = sites.count { stamped.contains($0.id) }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(done)")
                    .font(UnigridStyle.figure)
                    .monospacedDigit()
                    .foregroundStyle(style.ink)
                Text("of \(sites.count) \(region.country.passportSlotNoun)")
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 16, maximum: 16), spacing: 4)],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(sites) { site in
                    Rectangle()
                        .fill(stamped.contains(site.id) ? ink : Color.clear)
                        .overlay { Rectangle().strokeBorder(ink, lineWidth: 1.5) }
                        .frame(width: 16, height: 16)
                        .help(site.name)
                }
            }
            .accessibilityHidden(true)
            if beyond > 0 {
                Text("\(beyond) more stamped beyond the \(region.country.passportSlotNoun)")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The fold between a spread's two pages.
struct BookGutter: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [style.rule.opacity(0), style.rule, style.rule.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 12)
            .overlay { Rectangle().fill(style.rule).frame(width: 1) }
            .accessibilityHidden(true)
    }
}
