import CoreGraphics

/// A park the icon can be drawn for: its name and designation for the brochure's band,
/// its land in `Heightfield.swift` (or `Abroad.swift`), its colours in `Land.swift` (or
/// `Abroad.swift`), and its plants in `Flora.swift`.
enum Scene: String, CaseIterable, Hashable {
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
    case fuji
    case jotunheimen
    case aoraki
    case moraineLake
    case cradleMountain

    /// What ships as the app's own icon. The rest are alternates the reader can pick.
    static let standard = Scene.zion

    /// The ten US parks the icon was first built for, in their original order.
    ///
    /// Their stacks are drawn from this ring and not from `allCases`, so adding a park
    /// abroad leaves every one of their icons exactly as it was approved.
    private static let unitedStates: [Scene] = [
        .zion, .grandCanyon, .yosemite, .sequoia, .rockyMountain,
        .olympic, .acadia, .joshuaTree, .everglades, .congaree,
    ]

    /// The list as it stood when the first two parks abroad joined it: the ten, then
    /// Fuji and Jotunheimen, closed on itself so their stacks are unchanged too.
    private static let firstAbroad: [Scene] = unitedStates + [.fuji, .jotunheimen]

    var parkName: String {
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
        case .fuji: "Fuji-Hakone-Izu"
        case .jotunheimen: "Jotunheimen"
        case .aoraki: "Aoraki/Mount Cook"
        case .moraineLake: "Banff"
        case .cradleMountain: "Cradle Mountain–Lake St Clair"
        }
    }

    /// The designation under the name, as the band carries it.
    ///
    /// The park and its state — or, abroad, its country — and nothing else. A real band
    /// also carries "National Park Service" and the Department of the Interior, and this
    /// one deliberately does not: `AGENTS.md` §5 forbids implying affiliation, and a line
    /// naming the agency would. The same goes for the parks abroad: no Ministry of the
    /// Environment, no Miljødirektoratet, no Department of Conservation, no Parks Canada,
    /// no Tasmania Parks and Wildlife Service, and no country's national park mark.
    var designation: String {
        switch self {
        case .zion: "National Park · Utah"
        case .grandCanyon: "National Park · Arizona"
        case .yosemite: "National Park · California"
        case .sequoia: "National Park · California"
        case .rockyMountain: "National Park · Colorado"
        case .olympic: "National Park · Washington"
        case .acadia: "National Park · Maine"
        case .joshuaTree: "National Park · California"
        case .everglades: "National Park · Florida"
        case .congaree: "National Park · South Carolina"
        case .fuji: "National Park · Japan"
        case .jotunheimen: "National Park · Norway"
        case .aoraki: "National Park · New Zealand"
        case .moraineLake: "National Park · Canada"
        case .cradleMountain: "National Park · Australia"
        }
    }

    /// The two brochures behind this one in the stack.
    ///
    /// The next two parks round the list, so every variant shows a different trio and no
    /// variant shows the same park twice. Each park goes round the list as it stood when
    /// it joined, closed on itself, so a park added later leaves every earlier stack —
    /// and every earlier icon — exactly as it was approved: the US ten round their own
    /// ring of ten, Fuji and Jotunheimen round those twelve (Jotunheimen and Zion under
    /// Fuji, Zion and the Grand Canyon under Jotunheimen), and the parks after them round
    /// the whole list (Banff and Cradle Mountain under Aoraki, Cradle Mountain and Zion
    /// under Banff, Zion and the Grand Canyon under Cradle Mountain).
    var others: [Scene] {
        let ring = [Scene.unitedStates, Scene.firstAbroad].first { $0.contains(self) }
            ?? Scene.allCases
        guard let index = ring.firstIndex(of: self) else { return [] }
        return [
            ring[(index + 1) % ring.count],
            ring[(index + 2) % ring.count],
        ]
    }

    /// The land's own colours, which belong to the park rather than to the brochure.
    ///
    /// `Palette` keeps the paper, the band and the accent — those are the same whichever
    /// park is standing behind them. Sandstone, granite, sawgrass and the Atlantic
    /// are not.
    func land(_ variant: Variant) -> Land {
        switch (self, variant) {
        case (_, .tinted): .tinted(seaLevel: landForm.seaLevel)
        case (.zion, .light): .zionLight
        case (.zion, .dark): .zionDark
        case (.grandCanyon, .light): .grandCanyonLight
        case (.grandCanyon, .dark): .grandCanyonDark
        case (.yosemite, .light): .yosemiteLight
        case (.yosemite, .dark): .yosemiteDark
        case (.sequoia, .light): .sequoiaLight
        case (.sequoia, .dark): .sequoiaDark
        case (.rockyMountain, .light): .rockyMountainLight
        case (.rockyMountain, .dark): .rockyMountainDark
        case (.olympic, .light): .olympicLight
        case (.olympic, .dark): .olympicDark
        case (.acadia, .light): .acadiaLight
        case (.acadia, .dark): .acadiaDark
        case (.joshuaTree, .light): .joshuaTreeLight
        case (.joshuaTree, .dark): .joshuaTreeDark
        case (.everglades, .light): .evergladesLight
        case (.everglades, .dark): .evergladesDark
        case (.congaree, .light): .congareeLight
        case (.congaree, .dark): .congareeDark
        case (.fuji, .light): .fujiLight
        case (.fuji, .dark): .fujiDark
        case (.jotunheimen, .light): .jotunheimenLight
        case (.jotunheimen, .dark): .jotunheimenDark
        case (.aoraki, .light): .aorakiLight
        case (.aoraki, .dark): .aorakiDark
        case (.moraineLake, .light): .moraineLakeLight
        case (.moraineLake, .dark): .moraineLakeDark
        case (.cradleMountain, .light): .cradleMountainLight
        case (.cradleMountain, .dark): .cradleMountainDark
        }
    }
}
