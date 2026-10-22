import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Months and years in a row with a visit: the run going now and the longest there has
/// been (SPECIFICATION.md §11).
struct StreaksSection: View {
    @Environment(\.unigrid) private var style
    let visits: [VisitSummary]

    var body: some View {
        let months = Streaks.months(visits)
        let years = Streaks.years(visits)
        VStack(alignment: .leading, spacing: 12) {
            SectionHead("In a row")
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                FigureBlock(
                    value: "\(months.current?.count ?? 0)",
                    label: (months.current?.count ?? 0) == 1 ? "Month, now" : "Months, now"
                )
                if let longest = months.longest {
                    FigureBlock(value: "\(longest.count)", label: "Most months, " + span(longest))
                }
                FigureBlock(
                    value: "\(years.current?.count ?? 0)",
                    label: (years.current?.count ?? 0) == 1 ? "Year, now" : "Years, now"
                )
                if let longest = years.longest, longest.count > 1 {
                    FigureBlock(
                        value: "\(longest.count)",
                        label: "Most years, " + yearSpan(longest)
                    )
                }
            }
            Text("A month or a year counts when at least one visit is logged in it.")
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
        }
    }

    private func span(_ run: Streaks.Run) -> String {
        let style = UnigridsFormat.month()
        return run.count == 1 ? run.first.formatted(style)
            : run.first.formatted(style) + "–" + run.last.formatted(style)
    }

    private func yearSpan(_ run: Streaks.Run) -> String {
        let calendar = Calendar.unigrids
        let first = calendar.component(.year, from: run.first)
        let last = calendar.component(.year, from: run.last)
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}

/// One year in parks: what was visited, what was new, how far was walked, and a card to
/// share it.
struct YearInReviewScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Query(sort: \Visit.date) private var visits: [Visit]
    @Query private var hikes: [Hike]

    @State private var year: Int?

    private var summaries: [VisitSummary] {
        visits.map(\.summary)
    }

    private var years: [Int] {
        YearInReview.years(in: summaries)
    }

    private var review: YearInReview? {
        (year ?? years.first).map {
            YearInReview(
                year: $0,
                places: store.places,
                visits: summaries,
                hikes: hikes.map(\.summary),
                trails: store.allTrails
            )
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BandHeader("Year in review", kicker: review.map { "\($0.year)" })
                VStack(alignment: .leading, spacing: 24) {
                    if years.count > 1 {
                        Picker("Year", selection: Binding(
                            get: { year ?? years.first ?? 0 },
                            set: { year = $0 }
                        )) {
                            ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let review {
                        YearCardContent(review: review)
                        ShareCardButton(title: "My \(review.year) in parks", weight: .primary) {
                            ShareCardFrame(title: "My \(review.year) in parks") {
                                YearCardContent(review: review)
                            }
                        }
                    } else {
                        Text("Log a visit and its year appears here.")
                            .font(UnigridStyle.proseSmall)
                            .foregroundStyle(style.inkSecondary)
                    }
                }
                .padding(UnigridStyle.pageMargin)
            }
        }
        .background(style.page)
        .navigationTitle("Year in review")
        .toolbarTitleDisplayMode(.inline)
    }
}

/// A year's figures and the national parks it brought, as the page and the card show them.
struct YearCardContent: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    let review: YearInReview

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 18
            ) {
                FigureBlock(
                    value: "\(review.visits)",
                    label: review.visits == 1 ? "Visit" : "Visits"
                )
                FigureBlock(
                    value: "\(review.places)",
                    label: review.places == 1 ? "Place" : "Places"
                )
                FigureBlock(value: "\(review.firstTimePlaces)", label: "New to you")
                FigureBlock(
                    value: "\(review.states.count)",
                    label: review.states.count == 1 ? "State" : "States and territories"
                )
                if review.trailsHiked > 0 {
                    FigureBlock(
                        value: UnigridsFormat.distance(metres: review.hikedMetres),
                        label: review.trailsHiked == 1 ? "Hiked, 1 trail"
                            : "Hiked, \(review.trailsHiked) trails"
                    )
                }
                if let month = review.busiestMonth {
                    FigureBlock(
                        value: Calendar.unigrids.monthSymbols[month - 1],
                        label: "Busiest month"
                    )
                }
            }
            if !review.nationalParks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHead(
                        "National parks",
                        detail: review.newNationalParks.isEmpty ? nil
                            : "\(review.newNationalParks.count) new"
                    )
                    ForEach(review.nationalParks, id: \.self) { id in
                        HStack(spacing: 10) {
                            if let place = store.place(id) {
                                PlaceMarker(
                                    tier: place.tier,
                                    tint: style.siteTint(for: place),
                                    status: .visited
                                )
                                .frame(width: 18)
                            }
                            Text(store.place(id)?.name ?? id.rawValue)
                                .font(UnigridStyle.rowTitle)
                                .foregroundStyle(style.ink)
                            if review.newNationalParks.contains(id) {
                                Text("NEW")
                                    .font(UnigridStyle.dataLabel)
                                    .foregroundStyle(style.accent)
                            }
                        }
                    }
                }
            }
            if !review.states.isEmpty {
                USTileMap(visited: Set(review.states.map(\.code)))
            }
        }
    }
}
