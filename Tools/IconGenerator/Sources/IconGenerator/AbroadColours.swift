import CoreGraphics

// The colours of the parks abroad, whose land is in `Abroad.swift`.

extension Land {
    /// A clear morning from the lakes. The cone's bare flanks are dark volcanic
    /// cinder, which the distance turns slate-blue under the white cap; the
    /// hills in front are forest, and the lake takes the sky.
    static let fujiLight = Land(
        sky: Ink(hex: 0x3A7EC4),
        skyHorizon: Ink(hex: 0xCADCEA),
        ridges: [
            Ink(hex: 0x4A5268), Ink(hex: 0x41484E), Ink(hex: 0x3A4A40),
            Ink(hex: 0x2E4230), Ink(hex: 0x243822),
        ],
        floor: Ink(hex: 0x2E4A2E),
        sun: Ink(hex: 0xF0E8D2),
        haze: Ink(hex: 0xC2D0E0),
        cloud: Ink(hex: 0xF2F6F8),
        vegetation: Ink(hex: 0x2A4C2C),
        sea: Ink(hex: 0x2A6894),
        seaLevel: Scene.fuji.landForm.seaLevel,
        snow: Ink(hex: 0xF4F7FA),
        greenery: 0.90
    )

    static let fujiDark = Land(
        sky: Ink(hex: 0x0B1322),
        skyHorizon: Ink(hex: 0x262A34),
        ridges: [
            Ink(hex: 0x30323E), Ink(hex: 0x282C36), Ink(hex: 0x1E2824),
            Ink(hex: 0x18221B), Ink(hex: 0x121A14),
        ],
        floor: Ink(hex: 0x142016),
        sun: Ink(hex: 0x262C38),
        haze: Ink(hex: 0x161E2A),
        cloud: Ink(hex: 0x242C38),
        vegetation: Ink(hex: 0x0F1D13),
        sea: Ink(hex: 0x10263A),
        seaLevel: Scene.fuji.landForm.seaLevel,
        // Moonlit, as Olympic's cap is: the brightest thing in the frame without
        // being the daylight white.
        snow: Ink(hex: 0xB0BAC6),
        greenery: 0.90
    )

    /// Dark rock — much of Jotunheimen is gabbro and its kin, near black when
    /// wet and a dark warm grey in sun; grey-green heath above the birch; the
    /// birch itself, a lighter and yellower green than any conifer; and the lake
    /// the milky green Gjende is, from the rock flour its glacial water carries.
    static let jotunheimenLight = Land(
        sky: Ink(hex: 0x3C7CC0),
        skyHorizon: Ink(hex: 0xC8D8E6),
        ridges: [
            Ink(hex: 0x585654), Ink(hex: 0x484644), Ink(hex: 0x3A3734),
            Ink(hex: 0x4A4A3C), Ink(hex: 0x34421F),
        ],
        floor: Ink(hex: 0x4E5A38),
        sun: Ink(hex: 0xEEEAD8),
        haze: Ink(hex: 0xCCD8E4),
        cloud: Ink(hex: 0xF4F8FA),
        vegetation: Ink(hex: 0x40592C),
        sea: Ink(hex: 0x3A8C7E),
        seaLevel: Scene.jotunheimen.landForm.seaLevel,
        snow: Ink(hex: 0xF4F7FA),
        greenery: 0.40,
        leaf: Ink(hex: 0x6E8C3A)
    )

    static let jotunheimenDark = Land(
        sky: Ink(hex: 0x0A1120),
        skyHorizon: Ink(hex: 0x252934),
        ridges: [
            Ink(hex: 0x3C424C), Ink(hex: 0x323840), Ink(hex: 0x282D34),
            Ink(hex: 0x22261E), Ink(hex: 0x181D15),
        ],
        floor: Ink(hex: 0x1A2016),
        sun: Ink(hex: 0x242C38),
        haze: Ink(hex: 0x161E2C),
        cloud: Ink(hex: 0x242C3A),
        vegetation: Ink(hex: 0x16221A),
        sea: Ink(hex: 0x12302C),
        seaLevel: Scene.jotunheimen.landForm.seaLevel,
        // Moonlit, as the Rocky Mountain snow is: there is more snow in this
        // frame than in any other, and left white it made the night icon glare.
        snow: Ink(hex: 0x8E98A6),
        greenery: 0.40,
        leaf: Ink(hex: 0x26321C)
    )

    /// Greywacke grey on the mountain and the moraine; tussock, gold-brown, on whatever
    /// ground will hold it; and Hooker Lake the milky grey-green of a glacier's silt.
    static let aorakiLight = Land(
        sky: Ink(hex: 0x3A7CC2),
        skyHorizon: Ink(hex: 0xCADBE8),
        ridges: [
            Ink(hex: 0x8E8C8A), Ink(hex: 0x7A7774), Ink(hex: 0x6E6A64),
            Ink(hex: 0x6A6862), Ink(hex: 0x6E6A5C),
        ],
        floor: Ink(hex: 0xA08C5A),
        sun: Ink(hex: 0xF0EAD8),
        haze: Ink(hex: 0xCCD8E4),
        cloud: Ink(hex: 0xF4F8FA),
        vegetation: Ink(hex: 0x9E8A58),
        sea: Ink(hex: 0x8AA6A8),
        seaLevel: Scene.aoraki.landForm.seaLevel,
        snow: Ink(hex: 0xF6F8FA),
        greenery: 0.35
    )

    /// Moonlit snow, as Olympic's is.
    static let aorakiDark = Land(
        sky: Ink(hex: 0x0A1120),
        skyHorizon: Ink(hex: 0x252934),
        ridges: [
            Ink(hex: 0x3E4450), Ink(hex: 0x343A44), Ink(hex: 0x2C3038),
            Ink(hex: 0x2A2A24), Ink(hex: 0x22221A),
        ],
        floor: Ink(hex: 0x24221A),
        sun: Ink(hex: 0x242C38),
        haze: Ink(hex: 0x161E2C),
        cloud: Ink(hex: 0x242C3A),
        vegetation: Ink(hex: 0x2E2A1C),
        sea: Ink(hex: 0x24343A),
        seaLevel: Scene.aoraki.landForm.seaLevel,
        snow: Ink(hex: 0xA8B2BE),
        greenery: 0.85
    )

    /// Quartzite and shale, grey-brown, over spruce and fir; and the lake the colour
    /// it is famous for, which no other water in the set comes near.
    static let moraineLakeLight = Land(
        sky: Ink(hex: 0x3A7EC4),
        skyHorizon: Ink(hex: 0xC8DAE8),
        ridges: [
            Ink(hex: 0x5E554E), Ink(hex: 0x524A44), Ink(hex: 0x5E5A54),
            Ink(hex: 0x3E5636), Ink(hex: 0x2C4228),
        ],
        floor: Ink(hex: 0x2E4A2E),
        sun: Ink(hex: 0xF0EAD8),
        haze: Ink(hex: 0xC8D6E2),
        cloud: Ink(hex: 0xF4F8FA),
        vegetation: Ink(hex: 0x2A4A2E),
        sea: Ink(hex: 0x1EA4B8),
        seaLevel: Scene.moraineLake.landForm.seaLevel,
        snow: Ink(hex: 0xF4F7FA),
        greenery: 0.8
    )

    static let moraineLakeDark = Land(
        sky: Ink(hex: 0x0A1120),
        skyHorizon: Ink(hex: 0x252934),
        ridges: [
            Ink(hex: 0x3C424C), Ink(hex: 0x323840), Ink(hex: 0x2C3036),
            Ink(hex: 0x1C261C), Ink(hex: 0x141C15),
        ],
        floor: Ink(hex: 0x142016),
        sun: Ink(hex: 0x242C38),
        haze: Ink(hex: 0x161E2C),
        cloud: Ink(hex: 0x242C3A),
        vegetation: Ink(hex: 0x0F1D13),
        sea: Ink(hex: 0x0E3A44),
        seaLevel: Scene.moraineLake.landForm.seaLevel,
        snow: Ink(hex: 0x9AA4B2),
        greenery: 0.8
    )

    /// Dolerite, a dark warm grey-brown; olive scrub and buttongrass under it; and Dove
    /// Lake dark and deep, its water stained by the peat it drains.
    static let cradleMountainLight = Land(
        sky: Ink(hex: 0x3C7CC0),
        skyHorizon: Ink(hex: 0xCCDCE8),
        ridges: [
            Ink(hex: 0x5A4C42), Ink(hex: 0x50463E), Ink(hex: 0x56583C),
            Ink(hex: 0x5E6A3C), Ink(hex: 0x4A5A30),
        ],
        floor: Ink(hex: 0x4E5A34),
        sun: Ink(hex: 0xF0E8D2),
        haze: Ink(hex: 0xC8D4DE),
        cloud: Ink(hex: 0xF4F8FA),
        vegetation: Ink(hex: 0x4A5C2E),
        sea: Ink(hex: 0x2A5674),
        seaLevel: Scene.cradleMountain.landForm.seaLevel,
        snow: Ink(hex: 0xF4F7FA),
        greenery: 0.85
    )

    static let cradleMountainDark = Land(
        sky: Ink(hex: 0x0A1120),
        skyHorizon: Ink(hex: 0x252934),
        ridges: [
            Ink(hex: 0x44464E), Ink(hex: 0x383A42), Ink(hex: 0x2A3026),
            Ink(hex: 0x22281E), Ink(hex: 0x181E14),
        ],
        floor: Ink(hex: 0x182014),
        sun: Ink(hex: 0x242C38),
        haze: Ink(hex: 0x161E2C),
        cloud: Ink(hex: 0x242C3A),
        vegetation: Ink(hex: 0x141E12),
        sea: Ink(hex: 0x0E1E2C),
        seaLevel: Scene.cradleMountain.landForm.seaLevel,
        snow: Ink(hex: 0x8E98A6),
        greenery: 0.85
    )
}
