import Foundation

/// Which park's icon the app wears.
///
/// The icon is a stack of Unigrid brochures over a park; this picks the park. It is a
/// per-device display preference like the palette, not part of the reader's log, so it
/// does not sync (`AppearanceDefaults`).
///
/// The raw values are the alternate-icon names registered in the Xcode target's
/// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`, and `nil` for `zion` because the
/// primary icon has no alternate name — that is the contract `setAlternateIconName`
/// expects, and it is why the default case is spelled out rather than inferred.
public enum AppIconChoice: String, CaseIterable, Sendable, Identifiable, Codable {
    case zion
    case grandCanyon
    case yosemite
    case sequoia
    case rockyMountain
    case olympic
    case acadia
    case joshuaTree
    case everglades
    case congaree

    public static let standard = AppIconChoice.zion

    public var id: String {
        rawValue
    }

    public var name: String {
        switch self {
        case .zion: "Zion"
        case .grandCanyon: "Grand Canyon"
        case .yosemite: "Yosemite"
        case .sequoia: "Sequoia"
        case .rockyMountain: "Rocky Mountain"
        case .olympic: "Olympic"
        case .acadia: "Acadia"
        case .joshuaTree: "Joshua Tree"
        case .everglades: "Everglades"
        case .congaree: "Congaree"
        }
    }

    public var state: String {
        switch self {
        case .zion: "Utah"
        case .grandCanyon: "Arizona"
        case .yosemite: "California"
        case .sequoia: "California"
        case .rockyMountain: "Colorado"
        case .olympic: "Washington"
        case .acadia: "Maine"
        case .joshuaTree: "California"
        case .everglades: "Florida"
        case .congaree: "South Carolina"
        }
    }

    /// The name UIKit knows this icon by, or `nil` for the one the app ships with.
    public var alternateIconName: String? {
        self == .standard ? nil : "AppIcon-\(rawValue)"
    }

    /// The choice an alternate-icon name maps back to, for reading the current icon at
    /// launch. An unknown name — an icon removed in a later release, say — reads as the
    /// default rather than throwing the picker into a state it cannot show.
    public static func named(_ alternateIconName: String?) -> AppIconChoice {
        guard let alternateIconName else { return .standard }
        return allCases.first { $0.alternateIconName == alternateIconName } ?? .standard
    }
}
