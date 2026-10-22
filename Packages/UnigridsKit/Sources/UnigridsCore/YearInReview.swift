import Foundation

/// Runs of getting out (SPECIFICATION.md §11): months, and years, in a row with at least
/// one visit logged.
public enum Streaks {
    /// A run of consecutive months or years: how many, and the first and last of them.
    public struct Run: Hashable, Sendable {
        public let count: Int
        /// The start of the run's first month or year, and of its last.
        public let first: Date
        public let last: Date
    }

    public struct Result: Hashable, Sendable {
        /// The longest run there has been.
        public let longest: Run?
        /// The run still going: one that includes this month (or year), or the last, which
        /// this one can still extend.
        public let current: Run?
    }

    public static func months(
        _ visits: [VisitSummary],
        now: Date = Date(),
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> Result {
        runs(visits, now: now, calendar: calendar) { components in
            (components.year ?? 0) * 12 + (components.month ?? 1) - 1
        } start: { index in
            DateComponents(year: index / 12, month: index % 12 + 1, day: 1)
        }
    }

    public static func years(
        _ visits: [VisitSummary],
        now: Date = Date(),
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> Result {
        runs(visits, now: now, calendar: calendar) { $0.year ?? 0 } start: { index in
            DateComponents(year: index, month: 1, day: 1)
        }
    }

    private static func runs(
        _ visits: [VisitSummary],
        now: Date,
        calendar: Calendar,
        index: (DateComponents) -> Int,
        start: (Int) -> DateComponents
    ) -> Result {
        let periods = Set(visits.map {
            index(calendar.dateComponents([.year, .month], from: $0.date))
        }).sorted()
        guard let firstPeriod = periods.first else { return Result(longest: nil, current: nil) }
        var spans: [(first: Int, last: Int)] = [(firstPeriod, firstPeriod)]
        for period in periods.dropFirst() {
            if period == spans[spans.count - 1].last + 1 {
                spans[spans.count - 1].last = period
            } else {
                spans.append((period, period))
            }
        }
        func run(_ span: (first: Int, last: Int)) -> Run? {
            guard let first = calendar.date(from: start(span.first)),
                  let last = calendar.date(from: start(span.last))
            else { return nil }
            return Run(count: span.last - span.first + 1, first: first, last: last)
        }
        // The earliest of the longest, so a tie keeps the run that set the record.
        let longest = spans.max { ($0.last - $0.first, $1.first) < ($1.last - $1.first, $0.first) }
        let today = index(calendar.dateComponents([.year, .month], from: now))
        let current = spans.last.flatMap { $0.last >= today - 1 ? $0 : nil }
        return Result(longest: longest.flatMap(run), current: current.flatMap(run))
    }
}

/// One year in parks, for the Year in review page and its share card.
public struct YearInReview: Hashable, Sendable {
    public let year: Int
    public let visits: Int
    /// Distinct places visited that year.
    public let places: Int
    /// Places visited that year for the first time ever.
    public let firstTimePlaces: Int
    /// National parks visited that year, and those that were new.
    public let nationalParks: [UnigridsID]
    public let newNationalParks: [UnigridsID]
    /// States and territories the year's places lie in.
    public let states: [USState]
    /// The month with the most visits, 1-based; the earliest of a tie.
    public let busiestMonth: Int?
    public let firstVisit: VisitSummary?
    public let lastVisit: VisitSummary?
    /// Hiked distance and climb, by the same rule as the Stats tab: a partial hike counts
    /// half.
    public let hikedMetres: Double
    public let climbedMetres: Double
    public let trailsHiked: Int

    /// Years with at least one visit, latest first.
    public static func years(
        in visits: [VisitSummary],
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> [Int] {
        Set(visits.map { calendar.component(.year, from: $0.date) }).sorted(by: >)
    }

    public init(
        year: Int,
        places: [Place],
        visits allVisits: [VisitSummary],
        hikes allHikes: [HikeSummary] = [],
        trails: [Trail] = [],
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) {
        let byID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = allVisits.sorted { $0.date < $1.date }
        let visits = sorted.filter { calendar.component(.year, from: $0.date) == year }
        let before = Set(sorted.filter { calendar.component(.year, from: $0.date) < year }
            .map(\.placeID))
        let ids = Set(visits.map(\.placeID))
        let parks = ids.filter { byID[$0]?.tier == .nationalPark }
            .sorted { $0.rawValue < $1.rawValue }

        self.year = year
        self.visits = visits.count
        self.places = ids.count
        firstTimePlaces = ids.subtracting(before).count
        nationalParks = parks
        newNationalParks = parks.filter { !before.contains($0) }
        states = Set(ids.compactMap { byID[$0] }.flatMap(\.states))
            .sorted { $0.code < $1.code }
        let months = Dictionary(grouping: visits) { calendar.component(.month, from: $0.date) }
        busiestMonth = months.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
        firstVisit = visits.first
        lastVisit = visits.last

        let trailsByID = Dictionary(
            trails.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let hikes = allHikes.filter { calendar.component(.year, from: $0.date) == year }
        var distance = 0.0
        var climb = 0.0
        for hike in hikes {
            guard let trail = trailsByID[hike.trailID] else { continue }
            let share = hike.completion == .full ? 1.0 : 0.5
            distance += trail.walkedMetres * share
            climb += (trail.climbMetres ?? 0) * share
        }
        hikedMetres = distance
        climbedMetres = climb
        trailsHiked = Set(hikes.map(\.trailID)).count
    }
}
