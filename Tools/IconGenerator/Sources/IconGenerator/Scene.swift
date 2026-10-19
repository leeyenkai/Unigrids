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
}

/// The park standing up out of the brochures, the way a pop-up book opens.
///
/// Depth is carried by four things and none of them is a gradient: planes **overlap**,
/// each one steps **paler** than the one in front (atmospheric perspective, quantised
/// rather than blended), the nearest is the **largest**, and every edge stays **hard**.
/// A ridge is a polygon, not a picture of a mountain: its profile is the park's own
/// section, and a shape that carries no fact comes out.
enum Scene: Hashable {
    case zion
    case yosemite
    case acadia

    /// The designation under the name, as the band carries it.
    ///
    /// The park and its state, and nothing else. A real band also carries "National Park
    /// Service" and the Department of the Interior, and this one deliberately does not:
    /// `AGENTS.md` §5 forbids implying affiliation, and a line naming the agency would.
    var designation: String {
        switch self {
        case .zion: "National Park · Utah"
        case .yosemite: "National Park · California"
        case .acadia: "National Park · Maine"
        }
    }

    var behindDesignation: String {
        switch self {
        case .zion: "National Park · California"
        case .yosemite: "National Park · Utah"
        case .acadia: "National Park · Utah"
        }
    }

    /// The park on the front brochure, and the one glimpsed behind it.
    var parkName: String {
        switch self {
        case .zion: "Zion"
        case .yosemite: "Yosemite"
        case .acadia: "Acadia"
        }
    }

    var behind: String {
        switch self {
        case .zion: "Yosemite"
        case .yosemite: "Zion"
        case .acadia: "Zion"
        }
    }

    /// The land's own colours, which belong to the park rather than to the brochure.
    ///
    /// `Palette` keeps the paper, the band and the accent — those are the same whichever
    /// park is standing behind them. Sandstone and granite are not.
    func land(_ variant: Variant) -> Land {
        switch (self, variant) {
        case (.zion, .light):
            // Navajo Sandstone: white upper beds for want of iron, pink middle,
            // red-brown lower with hematite, under the deep sky of the Plateau.
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
                seaLevel: 0
            )
        case (.zion, .dark):
            Land(
                sky: Ink(hex: 0x0E1726),
                skyHorizon: Ink(hex: 0x2E3038),
                ridges: [
                    // Each darker than the sky above it. Lit brighter than the zenith,
                    // a distant ridge stops reading as rock and starts reading as a
                    // hole punched through to the sky.
                    Ink(hex: 0x2B313B), Ink(hex: 0x39332A), Ink(hex: 0x4C3522),
                    Ink(hex: 0x382013), Ink(hex: 0x24110A),
                ],
                floor: Ink(hex: 0x3A2318),
                sun: Ink(hex: 0x3E2A20),
                haze: Ink(hex: 0x1C2230),
                cloud: Ink(hex: 0x2A3242),
                vegetation: Ink(hex: 0x1E2A18),
                sea: Ink(hex: 0x14293A),
                seaLevel: 0
            )
        case (.yosemite, .light):
            // Granite is "salt-and-pepper" — light quartz and feldspar against dark
            // biotite and hornblende — and the valley floor is meadow and pine.
            Land(
                sky: Ink(hex: 0x3A80BE),
                skyHorizon: Ink(hex: 0xCCDFE8),
                ridges: [
                    Ink(hex: 0xE4E9EB), Ink(hex: 0xC2CDD3), Ink(hex: 0x9AA8B0),
                    Ink(hex: 0x74838C), Ink(hex: 0x4E5C66),
                ],
                floor: Ink(hex: 0x7C8C5C),
                sun: Ink(hex: 0xE8E2C4),
                haze: Ink(hex: 0xD8E2E6),
                cloud: Ink(hex: 0xF2F6F8),
                vegetation: Ink(hex: 0x375B2E),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: 0
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
                seaLevel: 0
            )
        case (.acadia, .light):
            // Pink granite ground down by ice, dark spruce on every shoulder, and the
            // Atlantic. Acadia is the one park of the three whose colour is mostly not
            // its rock.
            Land(
                sky: Ink(hex: 0x4A8CC2),
                skyHorizon: Ink(hex: 0xCFE0EA),
                ridges: [
                    Ink(hex: 0xE4D8D0), Ink(hex: 0xCDB4AA), Ink(hex: 0xAC8E86),
                    Ink(hex: 0x836C66), Ink(hex: 0x5C4C48),
                ],
                floor: Ink(hex: 0x6E7A5E),
                sun: Ink(hex: 0xF0E4CC),
                haze: Ink(hex: 0xD6E0E6),
                cloud: Ink(hex: 0xF4F8FA),
                vegetation: Ink(hex: 0x2C4733),
                sea: Ink(hex: 0x2A6B8E),
                seaLevel: 0.062
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
                seaLevel: 0.062
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
                seaLevel: 0
            )
        }
    }
}
