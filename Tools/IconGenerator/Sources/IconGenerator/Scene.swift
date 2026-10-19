import CoreGraphics

/// One park's land, in one appearance.
struct Land {
    /// Overhead.
    let sky: Ink
    /// At the horizon, where haze pales it. The sky is a gradient between the two.
    let skyHorizon: Ink
    /// Far to near. Each step warmer and darker than the one behind it, which is
    /// atmospheric perspective done in discrete steps instead of a blend.
    let ridges: [Ink]
    /// The valley floor, in the cover's photograph.
    let floor: Ink
    /// The low sun's bloom.
    let sun: Ink
    /// The colour of the air itself, washed over the terrain with distance.
    let haze: Ink
    /// Cloud.
    let cloud: Ink
    /// Cottonwood on the floor and scrub on the ledges — most of the colour in either
    /// park that is not rock.
    let vegetation: Ink
    /// The sea, and the height it stands at. Zero for a park that has none.
    let sea: Ink
    let seaLevel: Double
    /// Lying snow.
    let snow: Ink
    /// How much of the ground carries plants, 0...1.
    ///
    /// One rule for every park turned Joshua Tree into rolling pasture. A desert is
    /// defined by what will not grow on it as much as a rainforest is by what will, so
    /// this is as much a part of a park's identity as the colour of its rock.
    let greenery: Double
    /// Bark, for a park whose trees are known by it. Nil takes it from the canopy.
    var bark: Ink?
}

/// A park the icon can be drawn for: its name and designation for the brochure's band,
/// its land in `Heightfield.swift`, its colours here, and its plants in `Flora.swift`.
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

    /// What ships as the app's own icon. The rest are alternates the reader can pick.
    static let standard = Scene.zion

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
        }
    }

    /// The designation under the name, as the band carries it.
    ///
    /// The park and its state, and nothing else. A real band also carries "National Park
    /// Service" and the Department of the Interior, and this one deliberately does not:
    /// `AGENTS.md` §5 forbids implying affiliation, and a line naming the agency would.
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
        }
    }

    /// The two brochures behind this one in the stack.
    ///
    /// The next two parks round the list, so every variant shows a different trio and no
    /// variant shows the same park twice.
    var others: [Scene] {
        let all = Scene.allCases
        guard let index = all.firstIndex(of: self) else { return [] }
        return [
            all[(index + 1) % all.count],
            all[(index + 2) % all.count],
        ]
    }

    /// The land's own colours, which belong to the park rather than to the brochure.
    ///
    /// `Palette` keeps the paper, the band and the accent — those are the same whichever
    /// park is standing behind them. Sandstone, granite, sawgrass and the Atlantic
    /// are not.
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func land(_ variant: Variant) -> Land {
        switch (self, variant) {
        case (.zion, .light):
            Land(
                sky: Ink(hex: 0x3E82BE),
                skyHorizon: Ink(hex: 0xC6DCE8),
                ridges: [
                    Ink(hex: 0xF0E2CA), Ink(hex: 0xE4BC8C), Ink(hex: 0xD2884C),
                    Ink(hex: 0xB85526), Ink(hex: 0x8E3315),
                ],
                floor: Ink(hex: 0xC8A982),
                sun: Ink(hex: 0xF2D8A8),
                haze: Ink(hex: 0xE6D5BE),
                cloud: Ink(hex: 0xEFF4F6),
                vegetation: Ink(hex: 0x44682C),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.zion, .dark):
            Land(
                sky: Ink(hex: 0x0E1726),
                skyHorizon: Ink(hex: 0x2E3038),
                ridges: [
                    Ink(hex: 0x2B313B), Ink(hex: 0x39332A), Ink(hex: 0x4C3522),
                    Ink(hex: 0x382013), Ink(hex: 0x24110A),
                ],
                floor: Ink(hex: 0x3A2318),
                sun: Ink(hex: 0x3E2A20),
                haze: Ink(hex: 0x1C2230),
                cloud: Ink(hex: 0x2A3242),
                vegetation: Ink(hex: 0x1E2A18),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.grandCanyon, .light):
            Land(
                sky: Ink(hex: 0x3C7FBE),
                skyHorizon: Ink(hex: 0xCBDCE6),
                ridges: [
                    Ink(hex: 0xE8E0CE), Ink(hex: 0xD9C49C), Ink(hex: 0xC06A42),
                    Ink(hex: 0xA8422A), Ink(hex: 0x8A4A3E),
                ],
                floor: Ink(hex: 0xB07A54),
                sun: Ink(hex: 0xF0D8AC),
                haze: Ink(hex: 0xE2D2C0),
                cloud: Ink(hex: 0xF0F4F6),
                vegetation: Ink(hex: 0x4C6334),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.26
            )
        case (.grandCanyon, .dark):
            Land(
                sky: Ink(hex: 0x0D1524),
                skyHorizon: Ink(hex: 0x2C2E36),
                ridges: [
                    Ink(hex: 0x2A2E34), Ink(hex: 0x342C24), Ink(hex: 0x42281C),
                    Ink(hex: 0x34180F), Ink(hex: 0x281713),
                ],
                floor: Ink(hex: 0x2E1C14),
                sun: Ink(hex: 0x3A2820),
                haze: Ink(hex: 0x1B212E),
                cloud: Ink(hex: 0x283040),
                vegetation: Ink(hex: 0x1C2616),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.26
            )
        case (.yosemite, .light):
            // Granite in sun is warm, not blue: off-white on the domes, buff-grey down
            // the walls, darkening where the water streaks run.
            Land(
                sky: Ink(hex: 0x3A80BE),
                skyHorizon: Ink(hex: 0xCCDFE8),
                ridges: [
                    Ink(hex: 0xECE7DD), Ink(hex: 0xD3CCBF), Ink(hex: 0xAFA799),
                    Ink(hex: 0x837D72), Ink(hex: 0x58554D),
                ],
                floor: Ink(hex: 0x7C8C5C),
                sun: Ink(hex: 0xE8E2C4),
                haze: Ink(hex: 0xD8E2E6),
                cloud: Ink(hex: 0xF2F6F8),
                vegetation: Ink(hex: 0x375B2E),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.78
            )
        case (.yosemite, .dark):
            Land(
                sky: Ink(hex: 0x0B1320),
                skyHorizon: Ink(hex: 0x272A33),
                ridges: [
                    Ink(hex: 0x3A4550), Ink(hex: 0x303A43), Ink(hex: 0x272F37),
                    Ink(hex: 0x1E252B), Ink(hex: 0x161C21),
                ],
                floor: Ink(hex: 0x2A3322),
                sun: Ink(hex: 0x25302C),
                haze: Ink(hex: 0x18202C),
                cloud: Ink(hex: 0x262E3C),
                vegetation: Ink(hex: 0x17241A),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.78
            )
        case (.sequoia, .light):
            // Granite and snow on the skyline; a floor of needles and bracken; and the
            // bark, which is the colour everyone remembers — cinnamon going to rust
            // where the sun is on it.
            Land(
                sky: Ink(hex: 0x3A7FBC),
                skyHorizon: Ink(hex: 0xC8DCE6),
                ridges: [
                    Ink(hex: 0xE6E3DC), Ink(hex: 0xC6C0B4), Ink(hex: 0x8F8D78),
                    Ink(hex: 0x5A633E), Ink(hex: 0x3C4A2C),
                ],
                floor: Ink(hex: 0x4A5432),
                sun: Ink(hex: 0xF2DCAE),
                haze: Ink(hex: 0xD2DEE2),
                cloud: Ink(hex: 0xF2F6F8),
                vegetation: Ink(hex: 0x3E5C2C),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.80,
                bark: Ink(hex: 0xA4552E)
            )
        case (.sequoia, .dark):
            Land(
                sky: Ink(hex: 0x0B1220),
                skyHorizon: Ink(hex: 0x262932),
                ridges: [
                    Ink(hex: 0x3C4248), Ink(hex: 0x30363C), Ink(hex: 0x262C28),
                    Ink(hex: 0x1C231C), Ink(hex: 0x151B15),
                ],
                floor: Ink(hex: 0x18271A),
                sun: Ink(hex: 0x2E3844),
                haze: Ink(hex: 0x18202C),
                cloud: Ink(hex: 0x262E3C),
                vegetation: Ink(hex: 0x16241A),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                // Moonlit, as the Rocky Mountain and Olympic snow is.
                snow: Ink(hex: 0x8E98A6),
                greenery: 0.80,
                bark: Ink(hex: 0x4A2A1E)
            )
        case (.rockyMountain, .light):
            // Summit to valley: the pink-grey granite of the Diamond, the gold-olive
            // of the alpine tundra above eleven thousand feet, then spruce and fir.
            // No white anywhere in the rock — the snow is drawn as snow, and a ramp
            // that is already white at the top leaves it nothing to stand out from.
            //
            // Granite in the top three beds, not one. The ramp is scaled to Zion's
            // relief, so the summits here only ever climb as far as the middle bed;
            // with tundra there, the whole range came out olive and the rock never
            // showed at all.
            Land(
                sky: Ink(hex: 0x3374BC),
                skyHorizon: Ink(hex: 0xC6D8E8),
                ridges: [
                    Ink(hex: 0xB8ACA6), Ink(hex: 0x9C8C86), Ink(hex: 0x7C706C),
                    Ink(hex: 0x76764E), Ink(hex: 0x32422C),
                ],
                floor: Ink(hex: 0x4A5E3E),
                sun: Ink(hex: 0xEDE8D4),
                haze: Ink(hex: 0xD4DEE8),
                cloud: Ink(hex: 0xF4F8FA),
                vegetation: Ink(hex: 0x2A4530),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.62
            )
        case (.rockyMountain, .dark):
            Land(
                sky: Ink(hex: 0x0A1120),
                skyHorizon: Ink(hex: 0x252934),
                ridges: [
                    Ink(hex: 0x3E4652), Ink(hex: 0x333A44), Ink(hex: 0x282E36),
                    Ink(hex: 0x1F242A), Ink(hex: 0x171B20),
                ],
                floor: Ink(hex: 0x1C2418),
                sun: Ink(hex: 0x242C38),
                haze: Ink(hex: 0x161E2C),
                cloud: Ink(hex: 0x242C3A),
                vegetation: Ink(hex: 0x141F17),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                // Moonlit, not lit. Most of this range is above the snowline, and snow left at its
                // daylight white made the night icon the brightest of the ten.
                snow: Ink(hex: 0x8E98A6),
                greenery: 0.62
            )
        case (.olympic, .light):
            // Basalt grey at the top, which only the volcano reaches and which shows
            // only in the gullies the snow will not hold in. Below it, rainforest to
            // the crests: the ridges in front of the mountain are Sitka spruce and
            // western hemlock all the way up, and pale rock there bleached the whole
            // middle of the frame.
            Land(
                sky: Ink(hex: 0x3C7CB4),
                skyHorizon: Ink(hex: 0xCEDDE2),
                ridges: [
                    Ink(hex: 0x8A9490), Ink(hex: 0x5C6C62), Ink(hex: 0x3E5646),
                    Ink(hex: 0x2E4636), Ink(hex: 0x22362A),
                ],
                floor: Ink(hex: 0x2E4A2E),
                sun: Ink(hex: 0xE6E8DC),
                haze: Ink(hex: 0xA8BCC0),
                cloud: Ink(hex: 0xF0F4F4),
                vegetation: Ink(hex: 0x1E3C24),
                sea: Ink(hex: 0x2C5E72),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.olympic, .dark):
            Land(
                sky: Ink(hex: 0x0A1220),
                skyHorizon: Ink(hex: 0x262B32),
                ridges: [
                    Ink(hex: 0x3A4440), Ink(hex: 0x2A3630), Ink(hex: 0x202C24),
                    Ink(hex: 0x18221C), Ink(hex: 0x121A15),
                ],
                floor: Ink(hex: 0x142316),
                sun: Ink(hex: 0x232B34),
                haze: Ink(hex: 0x161E28),
                cloud: Ink(hex: 0x242C36),
                vegetation: Ink(hex: 0x0E1C11),
                sea: Ink(hex: 0x0F2430),
                seaLevel: landForm.seaLevel,
                // Moonlit: still the brightest thing in the frame, as the mountain should be, but
                // not the daylight white that turned the near ridges into a glare.
                snow: Ink(hex: 0xB0BAC6),
                greenery: 1.0
            )
        case (.acadia, .light):
            // Cadillac granite is pink — salmon in sun, mauve in shadow — and the sea
            // against it is the cold green-blue of the Gulf of Maine.
            Land(
                sky: Ink(hex: 0x4A8CC2),
                skyHorizon: Ink(hex: 0xCFE0EA),
                // Pink to the waterline: the dark band down there is rockweed, drawn
                // as rockweed, and the rock under it is the same granite as the top.
                ridges: [
                    Ink(hex: 0xF0CDB8), Ink(hex: 0xE4B29A), Ink(hex: 0xD49A84),
                    Ink(hex: 0xBA806C), Ink(hex: 0x946252),
                ],
                floor: Ink(hex: 0x6E7A5E),
                sun: Ink(hex: 0xF4E2C8),
                haze: Ink(hex: 0xD6E0E6),
                cloud: Ink(hex: 0xF4F8FA),
                vegetation: Ink(hex: 0x2A4632),
                sea: Ink(hex: 0x245C78),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F8F8),
                greenery: 0.85
            )
        case (.acadia, .dark):
            Land(
                sky: Ink(hex: 0x0C1422),
                skyHorizon: Ink(hex: 0x2A3038),
                ridges: [
                    Ink(hex: 0x3A3632), Ink(hex: 0x332D2A), Ink(hex: 0x2A2422),
                    Ink(hex: 0x201B1A), Ink(hex: 0x171413),
                ],
                floor: Ink(hex: 0x1C2219),
                sun: Ink(hex: 0x30323A),
                haze: Ink(hex: 0x1E2630),
                cloud: Ink(hex: 0x282E3A),
                vegetation: Ink(hex: 0x151F18),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                // The surf, by moonlight.
                snow: Ink(hex: 0x7E8A98),
                greenery: 0.85
            )
        case (.joshuaTree, .light):
            Land(
                sky: Ink(hex: 0x4186C4),
                skyHorizon: Ink(hex: 0xD6E2E8),
                ridges: [
                    Ink(hex: 0xEFE4DC), Ink(hex: 0xDCC8BE), Ink(hex: 0xC2A89C),
                    Ink(hex: 0xA2887E), Ink(hex: 0x7C645C),
                ],
                floor: Ink(hex: 0xC6A886),
                sun: Ink(hex: 0xF4E2C0),
                haze: Ink(hex: 0xE4DACE),
                cloud: Ink(hex: 0xF2F6F8),
                vegetation: Ink(hex: 0x6E7A42),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.1
            )
        case (.joshuaTree, .dark):
            Land(
                sky: Ink(hex: 0x0E1626),
                skyHorizon: Ink(hex: 0x303038),
                ridges: [
                    Ink(hex: 0x32302E), Ink(hex: 0x2C2826), Ink(hex: 0x262120),
                    Ink(hex: 0x1E1A19), Ink(hex: 0x161312),
                ],
                floor: Ink(hex: 0x2A2218),
                sun: Ink(hex: 0x3A3026),
                haze: Ink(hex: 0x20242E),
                cloud: Ink(hex: 0x2C3240),
                vegetation: Ink(hex: 0x20241A),
                sea: Ink(hex: 0x14293A),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 0.1
            )
        case (.everglades, .light):
            Land(
                sky: Ink(hex: 0x3E88C6),
                skyHorizon: Ink(hex: 0xD2E2EA),
                ridges: [
                    Ink(hex: 0xD8D8B8), Ink(hex: 0xBCC098), Ink(hex: 0x9EA87C),
                    Ink(hex: 0x7E9064), Ink(hex: 0x5E7A4E),
                ],
                floor: Ink(hex: 0x6E8A4E),
                sun: Ink(hex: 0xF2E8C8),
                haze: Ink(hex: 0xDAE4E4),
                cloud: Ink(hex: 0xF4F8FA),
                vegetation: Ink(hex: 0x4C7034),
                sea: Ink(hex: 0x3E7E8C),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.everglades, .dark):
            Land(
                sky: Ink(hex: 0x0C1626),
                skyHorizon: Ink(hex: 0x2C3038),
                ridges: [
                    Ink(hex: 0x2A2E22), Ink(hex: 0x24281E), Ink(hex: 0x1F2319),
                    Ink(hex: 0x191D15), Ink(hex: 0x141811),
                ],
                floor: Ink(hex: 0x18220F),
                sun: Ink(hex: 0x323828),
                haze: Ink(hex: 0x1A222C),
                cloud: Ink(hex: 0x283040),
                vegetation: Ink(hex: 0x142012),
                sea: Ink(hex: 0x12303A),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.congaree, .light):
            Land(
                sky: Ink(hex: 0x3E86BE),
                skyHorizon: Ink(hex: 0xCEDEE6),
                ridges: [
                    Ink(hex: 0xCBD2AE), Ink(hex: 0xACB68C), Ink(hex: 0x8C9A6E),
                    Ink(hex: 0x6C7C54), Ink(hex: 0x4E5E3E),
                ],
                floor: Ink(hex: 0x3A4A2A),
                sun: Ink(hex: 0xEEE6C6),
                haze: Ink(hex: 0xD4DEE0),
                cloud: Ink(hex: 0xF2F6F8),
                vegetation: Ink(hex: 0x22401F),
                sea: Ink(hex: 0x2E3528),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (.congaree, .dark):
            Land(
                sky: Ink(hex: 0x0C1524),
                skyHorizon: Ink(hex: 0x2A2E36),
                ridges: [
                    Ink(hex: 0x262A20), Ink(hex: 0x20241B), Ink(hex: 0x1A1E16),
                    Ink(hex: 0x151912), Ink(hex: 0x101310),
                ],
                floor: Ink(hex: 0x121808),
                sun: Ink(hex: 0x2E3228),
                haze: Ink(hex: 0x18202A),
                cloud: Ink(hex: 0x262E3A),
                vegetation: Ink(hex: 0x0E1A0D),
                sea: Ink(hex: 0x13170F),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        case (_, .tinted):
            // Value alone has to carry the depth, so the steps are wider here than
            // colour would need them to be.
            Land(
                sky: Ink(hex: 0x3A3A3A),
                skyHorizon: Ink(hex: 0x5E5E5E),
                ridges: [
                    Ink(hex: 0xDCDCDC), Ink(hex: 0xBEBEBE), Ink(hex: 0x9C9C9C),
                    Ink(hex: 0x7A7A7A), Ink(hex: 0x5A5A5A),
                ],
                floor: Ink(hex: 0xC6C6C6),
                sun: Ink(hex: 0xE8E8E8),
                haze: Ink(hex: 0xD0D0D0),
                cloud: Ink(hex: 0xF0F0F0),
                vegetation: Ink(hex: 0x7C7C7C),
                sea: Ink(hex: 0x8E8E8E),
                seaLevel: landForm.seaLevel,
                snow: Ink(hex: 0xF4F7FA),
                greenery: 1.0
            )
        }
    }
}
