import Foundation

/// Which places the map shows (SPECIFICATION.md §5, "Filters").
///
/// A value rather than a set of view toggles so the rule — what a filter combination
/// actually lets through — is testable, and so the map, the legend and the filter sheet
/// read one definition.
public struct MapFilter: Hashable, Sendable, Codable {
    /// Whether to narrow by the reader's own log.
    public enum Visits: String, CaseIterable, Sendable, Codable, Identifiable {
        case all
        case visited
        case notVisited

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .all: "All places"
            case .visited: "Visited"
            case .notVisited: "Not yet visited"
            }
        }
    }

    /// Which kinds of site to show. Every type, to begin with.
    public var siteTypes: Set<SiteType>
    public var visits: Visits
    /// Subdivision codes to narrow to — `US-UT`, `JP-01`, `NO-34`. Empty means everywhere.
    /// A bare two-letter code, the form filters saved before 0.10.0 hold, is read as a US
    /// state; a code no longer known is dropped.
    public var states: Set<String>
    /// Activities a place must list, every one of them. Empty means any place. A place
    /// whose agency publishes no activity list never passes a narrowed filter: unknown is
    /// not the same as offered.
    public var activities: Set<PlaceActivity>
    /// Only places with an official passport stamp location.
    public var stampLocationsOnly: Bool

    public init(
        siteTypes: Set<SiteType> = Set(SiteType.allCases),
        visits: Visits = .all,
        states: Set<String> = [],
        activities: Set<PlaceActivity> = [],
        stampLocationsOnly: Bool = false
    ) {
        self.siteTypes = siteTypes
        self.visits = visits
        self.states = MapFilter.normalised(states)
        self.activities = activities
        self.stampLocationsOnly = stampLocationsOnly
    }

    private static func normalised(_ codes: some Sequence<String>) -> Set<String> {
        Set(codes.compactMap { Subdivision.named($0)?.code })
    }

    /// Everything, which is where the map starts.
    public static let everything = MapFilter()

    /// Whether the filter has narrowed anything, for the toolbar's filled-or-not icon.
    public var isNarrowed: Bool {
        self != .everything
    }

    /// How many separate things are narrowed, for a badge on the filter button.
    public var narrowedCount: Int {
        [
            siteTypes.count != SiteType.allCases.count,
            visits != .all,
            !states.isEmpty,
            !activities.isEmpty,
            stampLocationsOnly,
        ].count(where: \.self)
    }

    /// Show or hide a whole tier's types at once, for the key's group switches.
    public mutating func setTier(_ tier: PlaceTier, shown: Bool) {
        let types = SiteType.allCases.filter { $0.tier == tier }
        if shown {
            siteTypes.formUnion(types)
        } else {
            siteTypes.subtract(types)
        }
    }

    public func includes(_ place: Place, isVisited: Bool, hasStampLocation: Bool = false) -> Bool {
        guard siteTypes.contains(place.siteType) else { return false }
        if !states.isEmpty, !place.subdivisions.contains(where: { states.contains($0.code) }) {
            return false
        }
        if !activities.isEmpty, !activities.isSubset(of: Set(place.activities)) {
            return false
        }
        if stampLocationsOnly, !hasStampLocation {
            return false
        }
        switch visits {
        case .all: return true
        case .visited: return isVisited
        case .notVisited: return !isVisited
        }
    }
}

/// How a filter is kept between launches (`@AppStorage("map.filter")`).
///
/// Written by hand, field by field, because the synthesized form failed whole on any
/// change — a new field, or a kind of place it did not know — and a filter that fails to
/// decode silently becomes "everything". Kinds of site are stored as the ones hidden, not
/// the ones shown, so a kind added in a later release is shown rather than filtered out
/// by a choice made before it existed.
extension MapFilter {
    private enum CodingKeys: String, CodingKey {
        case siteTypes, hiddenSiteTypes, visits, states, activities, stampLocationsOnly
    }

    /// Every kind of site there was when filters stored the kinds shown. A filter saved
    /// then shows any kind added since.
    static let siteTypesBeforeHiddenList: Set<String> = [
        "nationalPark", "nationalMonument", "nationalPreserve", "historicSite",
        "battlefield", "memorial", "seashore", "recreationArea", "river", "parkway",
        "otherNPSSite", "statePark", "nationalForest", "nationalGrassland",
        "wildlifeRefuge", "conservationArea", "naturalLandmark", "scenicByway",
    ]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func strings(_ key: CodingKeys) -> [String]? {
            try? container.decodeIfPresent([String].self, forKey: key)
        }
        let all = Set(SiteType.allCases)
        if let hidden = strings(.hiddenSiteTypes) {
            siteTypes = all.subtracting(hidden.compactMap(SiteType.init(rawValue:)))
        } else if let shown = strings(.siteTypes) {
            let newer = all.filter { !Self.siteTypesBeforeHiddenList.contains($0.rawValue) }
            siteTypes = Set(shown.compactMap(SiteType.init(rawValue:))).union(newer)
        } else {
            siteTypes = all
        }
        visits = (try? container.decodeIfPresent(Visits.self, forKey: .visits)) ?? .all
        states = Self.normalised(strings(.states) ?? [])
        activities = Set((strings(.activities) ?? []).compactMap(PlaceActivity.init(rawValue:)))
        stampLocationsOnly = (try? container.decodeIfPresent(
            Bool.self, forKey: .stampLocationsOnly
        )) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let hidden = SiteType.allCases.filter { !siteTypes.contains($0) }.map(\.rawValue)
        try container.encode(hidden, forKey: .hiddenSiteTypes)
        try container.encode(visits, forKey: .visits)
        try container.encode(states.sorted(), forKey: .states)
        try container.encode(activities.map(\.rawValue).sorted(), forKey: .activities)
        try container.encode(stampLocationsOnly, forKey: .stampLocationsOnly)
    }
}

extension PlaceTier {
    /// The tier's name in the map legend and filters.
    public var name: String {
        switch self {
        case .nationalPark: "National parks"
        case .npsUnit: "Other NPS sites"
        case .statePark: "State parks"
        case .federalSite: "Other public lands"
        }
    }

    /// One line on what the tier covers, for the filter sheet.
    public var detail: String {
        switch self {
        case .nationalPark: "Every one with a full guide"
        case .npsUnit: "Monuments, historic sites, seashores, memorials and more"
        case .statePark: "A selection of well-known state parks"
        case .federalSite: "Forests, grasslands, refuges, BLM lands, landmarks and byways"
        }
    }
}

/// How much the map draws at a given zoom.
///
/// Every outline shows at every zoom — the reader asked to see the whole patchwork of
/// public land at once — but not at the same detail. Above a regional span, everything
/// except the national parks is drawn from the country-scale outlines, a tenth of the
/// vertices, and the full ones take over as the camera comes in. The thresholds are
/// latitude spans in degrees, the same figure MapKit reports for the visible region.
public enum MapDetail {
    /// The span every threshold below reads: the map's latitude span, scaled above 50°
    /// north or south by how much more the Mercator map stretches there than at 50°.
    ///
    /// Without it, the whole of Norway on a phone spans only some twenty degrees of
    /// latitude and reads as a regional view: forty-eight full-size park pins and their
    /// names piled on one another. Scaled, it reads at the detail the Lower 48 does when
    /// framed whole. Below 50° the span is unchanged, so the Lower 48, Hawaii and Japan
    /// draw exactly as before.
    public static func detailSpan(latitudeSpan: Double, centerLatitude: Double) -> Double {
        let reference = cos(50 * Double.pi / 180)
        let here = cos(min(abs(centerLatitude), 85) * Double.pi / 180)
        return latitudeSpan * max(1, reference / here)
    }

    /// Below this span, every outline is drawn at full detail. Above it, only national
    /// parks are.
    public static let allOutlinesSpan: Double = 14

    /// Whether a tier's outlines are drawn at a latitude span. Always, now; kept as the
    /// one place to say otherwise.
    public static func showsOutline(for _: PlaceTier, latitudeSpan _: Double) -> Bool {
        true
    }

    /// Whether a tier's outline comes from the country-scale set at a latitude span.
    public static func usesOverviewOutline(for tier: PlaceTier, latitudeSpan: Double) -> Bool {
        tier != .nationalPark && latitudeSpan > allOutlinesSpan
    }

    /// Whether a place's name is worth printing beside its pin at a latitude span. National
    /// parks are labelled from regional zoom; everything else only once the map is close.
    public static func showsLabel(for tier: PlaceTier, latitudeSpan: Double) -> Bool {
        switch tier {
        case .nationalPark: latitudeSpan <= 22
        case .npsUnit, .statePark, .federalSite: latitudeSpan <= 4
        }
    }

    /// Below this span, every pin carries its site type's pictogram. Above it the smaller
    /// sites are plain shapes: two thousand pictograms at country scale are noise.
    public static let pictogramSpan: Double = 12

    /// Whether a tier's pins carry their pictogram at a latitude span. National parks
    /// always do; they are few and they are the point.
    public static func showsPictogram(for tier: PlaceTier, latitudeSpan: Double) -> Bool {
        tier == .nationalPark || latitudeSpan <= pictogramSpan
    }

    /// Above this span — the whole country on screen — a national park's pin is drawn
    /// compact, because sixty-three full-size pins on a phone are a crowd.
    public static let compactParkSpan: Double = 22

    /// Whether pins carry their live-alert badge at a latitude span. From regional zoom
    /// only: at country scale nearly every park has some closure posted, and a badge on
    /// every pin says nothing.
    public static func showsAlertBadge(latitudeSpan: Double) -> Bool {
        latitudeSpan <= compactParkSpan
    }

    /// Below this span, Amtrak stations are marked on the rail layer.
    public static let stationSpan: Double = 6

    /// Whether a place gets a pin at a latitude span.
    ///
    /// The big lands — forests, grasslands, refuges, BLM lands — read as areas from afar,
    /// so their outlines stand for them at country scale and their pins come in with
    /// regional zoom. Landmarks, byways and state parks wait for regional zoom too: six
    /// hundred landmarks, or three and a half thousand state parks, at country scale are a
    /// blanket of cluster counts, not a map.
    public static func showsPin(for kind: PlaceKind, latitudeSpan: Double) -> Bool {
        switch kind {
        case .nationalPark, .npsUnit:
            true
        case .statePark, .nationalForest, .nationalGrassland, .wildlifeRefuge, .blmMonument,
             .blmConservationArea, .naturalLandmark, .scenicByway, .quasiNationalPark,
             .protectedLandscape, .natureReserve, .conservationPark, .stateNationalPark,
             .marineConservationArea, .provincialPark:
            latitudeSpan <= allOutlinesSpan
        }
    }

    /// Whether a byway's line is drawn at a latitude span. At country scale two hundred
    /// byways read as a road network, which is what the transport layers are for.
    public static func showsRoute(latitudeSpan: Double) -> Bool {
        latitudeSpan <= allOutlinesSpan
    }
}
