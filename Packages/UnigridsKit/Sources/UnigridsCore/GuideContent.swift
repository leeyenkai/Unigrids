import Foundation

/// An image used in a guide, with the credit it must carry.
///
/// `isPublicDomain` is not decoration. Only photographs confirmed public domain are
/// reused in native guides; anything uncertain stays inside the brochure viewer, shown as
/// published (SPECIFICATION.md §6, §15).
public struct GuideImage: Hashable, Sendable, Codable {
    /// Name of an asset bundled with the app, where the image ships with the release.
    public let assetName: String?
    /// Remote source, where the image is fetched and cached instead.
    public let url: URL?
    public let caption: String?
    public let credit: String
    public let isPublicDomain: Bool

    public init(
        assetName: String? = nil,
        url: URL? = nil,
        caption: String? = nil,
        credit: String,
        isPublicDomain: Bool
    ) {
        self.assetName = assetName
        self.url = url
        self.caption = caption
        self.credit = credit
        self.isPublicDomain = isPublicDomain
    }
}

/// One row of the guide's chronology panel, echoing the timelines in many Unigrid
/// brochures (SPECIFICATION.md §6, panel 10).
public struct ChronologyEntry: Hashable, Sendable, Codable, Identifiable {
    /// As published: "1909", "1919", "c. 1200", "1860s".
    public let year: String
    public let text: String

    public var id: String {
        year + text
    }

    public init(year: String, text: String) {
        self.year = year
        self.text = text
    }
}

/// The "Plan your visit" panel (SPECIFICATION.md §6, panel 9).
public struct PlanYourVisit: Hashable, Sendable, Codable {
    public var entrances: [String]
    /// Timed entry or reservation rules, as prose, because they change every season.
    public var reservations: String?
    public var permits: [String]
    public var camping: [String]
    public var lodging: [String]
    public var seasonalClosures: [String]

    public init(
        entrances: [String] = [],
        reservations: String? = nil,
        permits: [String] = [],
        camping: [String] = [],
        lodging: [String] = [],
        seasonalClosures: [String] = []
    ) {
        self.entrances = entrances
        self.reservations = reservations
        self.permits = permits
        self.camping = camping
        self.lodging = lodging
        self.seasonalClosures = seasonalClosures
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entrances = try container.decodeIfPresent([String].self, forKey: .entrances) ?? []
        reservations = try container.decodeIfPresent(String.self, forKey: .reservations)
        permits = try container.decodeIfPresent([String].self, forKey: .permits) ?? []
        camping = try container.decodeIfPresent([String].self, forKey: .camping) ?? []
        lodging = try container.decodeIfPresent([String].self, forKey: .lodging) ?? []
        seasonalClosures = try container.decodeIfPresent(
            [String].self, forKey: .seasonalClosures
        ) ?? []
    }

    public var isEmpty: Bool {
        entrances.isEmpty && reservations == nil && permits.isEmpty
            && camping.isEmpty && lodging.isEmpty && seasonalClosures.isEmpty
    }
}

/// A source the guide's text was adapted from.
public struct GuideSource: Hashable, Sendable, Codable, Identifiable {
    public let title: String
    public let url: URL?

    public var id: String {
        title
    }

    public init(title: String, url: URL? = nil) {
        self.title = title
        self.url = url
    }
}

/// The content of one park's native Unigrid-style guide (SPECIFICATION.md §6).
///
/// The panel *structure* is fixed by the template, so this is a plain struct rather than a
/// heterogeneous list: variation between parks is content, not layout. `panels` derives
/// the ordered list the grid lays out, skipping anything this park has no content for.
///
/// Text is adapted from public-domain NPS material, lightly edited for length and to fit
/// the panel structure.
public struct GuideContent: Hashable, Sendable, Codable, Identifiable {
    public let placeID: UnigridsID
    /// Bumped by the pipeline when the text changes, so a guide can be diffed per release.
    public let contentVersion: Int
    public let hero: GuideImage?
    /// Three or four short paragraphs on geology, ecology and history.
    public let story: [String]
    /// The official brochure map, public domain, shown interactively.
    public let mapImage: GuideImage?
    /// One line per sight, keyed by point-of-interest id, overriding its own summary.
    public let sightNotes: [String: String]
    public let trailHighlightIDs: [UnigridsID]
    public let planYourVisit: PlanYourVisit
    public let chronology: [ChronologyEntry]
    public let safety: [String]
    public let regulations: [String]
    public let credits: [String]
    public let sources: [GuideSource]

    public var id: UnigridsID {
        placeID
    }

    public init(
        placeID: UnigridsID,
        contentVersion: Int = 1,
        hero: GuideImage? = nil,
        story: [String] = [],
        mapImage: GuideImage? = nil,
        sightNotes: [String: String] = [:],
        trailHighlightIDs: [UnigridsID] = [],
        planYourVisit: PlanYourVisit = PlanYourVisit(),
        chronology: [ChronologyEntry] = [],
        safety: [String] = [],
        regulations: [String] = [],
        credits: [String] = [],
        sources: [GuideSource] = []
    ) {
        self.placeID = placeID
        self.contentVersion = contentVersion
        self.hero = hero
        self.story = story
        self.mapImage = mapImage
        self.sightNotes = sightNotes
        self.trailHighlightIDs = trailHighlightIDs
        self.planYourVisit = planYourVisit
        self.chronology = chronology
        self.safety = safety
        self.regulations = regulations
        self.credits = credits
        self.sources = sources
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeID = try container.decode(UnigridsID.self, forKey: .placeID)
        contentVersion = try container.decodeIfPresent(Int.self, forKey: .contentVersion) ?? 1
        hero = try container.decodeIfPresent(GuideImage.self, forKey: .hero)
        story = try container.decodeIfPresent([String].self, forKey: .story) ?? []
        mapImage = try container.decodeIfPresent(GuideImage.self, forKey: .mapImage)
        sightNotes = try container.decodeIfPresent(
            [String: String].self, forKey: .sightNotes
        ) ?? [:]
        trailHighlightIDs = try container.decodeIfPresent(
            [UnigridsID].self, forKey: .trailHighlightIDs
        ) ?? []
        planYourVisit = try container.decodeIfPresent(
            PlanYourVisit.self, forKey: .planYourVisit
        ) ?? PlanYourVisit()
        chronology = try container.decodeIfPresent(
            [ChronologyEntry].self, forKey: .chronology
        ) ?? []
        safety = try container.decodeIfPresent([String].self, forKey: .safety) ?? []
        regulations = try container.decodeIfPresent([String].self, forKey: .regulations) ?? []
        credits = try container.decodeIfPresent([String].self, forKey: .credits) ?? []
        sources = try container.decodeIfPresent([GuideSource].self, forKey: .sources) ?? []
    }
}

/// One panel of a rendered guide, in template order.
///
/// Derived from `GuideContent` plus the place's facts and points of interest — not stored,
/// so a guide can never carry a panel the data cannot fill.
public enum GuidePanel: Hashable, Sendable, Identifiable {
    case hero(GuideImage)
    case atAGlance
    case story
    case map(GuideImage)
    case majorSights
    case visitorCentres
    case trailHighlights
    case planYourVisit
    case chronology
    case safetyAndRegulations
    case creditsAndSources

    public var id: String {
        switch self {
        case .hero: "hero"
        case .atAGlance: "at-a-glance"
        case .story: "story"
        case .map: "map"
        case .majorSights: "major-sights"
        case .visitorCentres: "visitor-centres"
        case .trailHighlights: "trail-highlights"
        case .planYourVisit: "plan-your-visit"
        case .chronology: "chronology"
        case .safetyAndRegulations: "safety"
        case .creditsAndSources: "credits"
        }
    }

    /// The heading above the panel. The hero and map carry none — they are images on the
    /// grid, as in the brochures.
    public var title: String? {
        switch self {
        case .hero, .map: nil
        case .atAGlance: "At a glance"
        case .story: "The story"
        case .majorSights: "Major sights"
        case .visitorCentres: "Visitor centres"
        case .trailHighlights: "Trail highlights"
        case .planYourVisit: "Plan your visit"
        case .chronology: "Chronology"
        case .safetyAndRegulations: "Safety and regulations"
        case .creditsAndSources: "Credits and sources"
        }
    }

    /// How many grid columns the panel would like, when the grid has them to give.
    ///
    /// Images and the map read as brochure spreads; prose reads better in one column.
    public var preferredColumnSpan: Int {
        switch self {
        case .hero, .map: 2
        case .story: 2
        default: 1
        }
    }
}

extension GuideContent {
    /// The panels to render, in template order (SPECIFICATION.md §6).
    ///
    /// `sightCount`, `visitorCentreCount` and `hasTrails` come from the reference store, so
    /// the sights and visitor-centre panels appear only when there is something in them.
    public func panels(
        placeHasFacts: Bool,
        sightCount: Int,
        visitorCentreCount: Int,
        hasTrails: Bool
    ) -> [GuidePanel] {
        var panels: [GuidePanel] = []
        if let hero {
            panels.append(.hero(hero))
        }
        if placeHasFacts {
            panels.append(.atAGlance)
        }
        if !story.isEmpty {
            panels.append(.story)
        }
        if let mapImage {
            panels.append(.map(mapImage))
        }
        if sightCount > 0 {
            panels.append(.majorSights)
        }
        if visitorCentreCount > 0 {
            panels.append(.visitorCentres)
        }
        if hasTrails, !trailHighlightIDs.isEmpty {
            panels.append(.trailHighlights)
        }
        if !planYourVisit.isEmpty {
            panels.append(.planYourVisit)
        }
        if !chronology.isEmpty {
            panels.append(.chronology)
        }
        if !safety.isEmpty || !regulations.isEmpty {
            panels.append(.safetyAndRegulations)
        }
        if !credits.isEmpty || !sources.isEmpty {
            panels.append(.creditsAndSources)
        }
        return panels
    }
}
