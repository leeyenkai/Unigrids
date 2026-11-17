import SwiftUI
import UnigridsCore
import UnigridsReference

// The passport's books, one per country (ADR 0013, SPECIFICATION.md §9): the US book
// after the paper NPS passport, and Unigrids' own books for Japan and Norway.

extension Country {
    /// What a book's slots are for: "NPS sites" in the US book, national parks abroad.
    var passportSlotNoun: String {
        self == .unitedStates ? "NPS sites" : "national parks"
    }

    /// The section a region page gives to stamped places outside the system.
    var passportBeyondTitle: String {
        self == .unitedStates ? "Beyond the NPS" : "Beyond the national parks"
    }

    /// The note under a book's list of regions.
    var passportRegionsNote: String {
        switch self {
        case .unitedStates:
            "Regions follow the paper passport's nine. Sites outside the NPS go by their "
                + "state, and appear on a region's page once stamped."
        case .japan:
            "Japan has no paper passport. Its eight regions are Unigrids' own, after the "
                + "Ministry of the Environment offices that administer each park. "
                + "Quasi-national parks appear on a region's page once stamped."
        case .norway:
            "Norway has no paper passport. Its six regions are Unigrids' own, after the "
                + "landsdeler, with Svalbard a book of its own. Protected landscapes and "
                + "nature reserves appear on a region's page once stamped."
        }
    }
}

extension ReferenceStore {
    /// The countries with national parks in the bundled data, in book order. A country
    /// joins the passport only when its places ship.
    var passportBooks: [Country] {
        let present = Set(nationalParks.map(\.country))
        return Country.allCases.filter(present.contains)
    }
}

extension Country {
    /// Who publishes a park's official documents, in a sentence: "the NPS".
    var documentPublisher: String {
        switch self {
        case .unitedStates: "the NPS"
        case .japan: "the Ministry of the Environment"
        case .norway: "Norway's national parks"
        }
    }

    /// The same, as a name in a credit line.
    var documentPublisherName: String {
        switch self {
        case .unitedStates: "the National Park Service"
        case .japan: "Japan's Ministry of the Environment"
        case .norway: "Norges nasjonalparker"
        }
    }

    /// Where a park's documents live, as a reader would type it.
    var documentSite: String {
        switch self {
        case .unitedStates: "nps.gov"
        case .japan: "japan.travel"
        case .norway: "norgesnasjonalparker.no"
        }
    }
}

extension String {
    /// "the NPS" → "The NPS".
    var capitalisedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
