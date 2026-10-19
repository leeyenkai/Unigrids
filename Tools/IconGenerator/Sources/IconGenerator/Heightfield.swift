import Foundation

/// The shape of the ground, as a function rather than a mesh.
///
/// Noise alone gives rolling hills, which is what every procedural landscape looks like
/// and what neither of these parks looks like at all. The shaping afterwards is what
/// makes them themselves: a terrace or two for Zion, because sandstone weathers in steps
/// and those steps are the strata; smoothing and doming for Yosemite, because glaciated
/// granite does not step, it swells.
///
/// **Two octaves, not five.** This is an icon, and the detail a full fractal gives is
/// detail nobody will ever see: at 1024 px it reads as noise and at 64 px it is mud. Two
/// octaves at a large feature size gives a handful of big landforms, which is what the
/// eye actually uses to read a canyon.
extension Scene {
    /// Ground height at a point, in the same units as the camera's own height.
    func height(x: Double, z: Double) -> Double {
        switch self {
        case .zion: zionHeight(x: x, z: z)
        case .yosemite: yosemiteHeight(x: x, z: z)
        case .acadia: acadiaHeight(x: x, z: z)
        }
    }

    // MARK: - Zion

    /// A plateau with a canyon cut through it. The walls come from terracing, which is
    /// the same thing the real beds do: flat tread, steep riser, flat tread.
    private func zionHeight(x: Double, z: Double) -> Double {
        let base = Noise.fbm(x: x * 0.78, y: z * 0.48, octaves: 3)
        // Ridged, so the high ground is sharp-edged rather than rounded.
        let ridged = 1 - abs(base * 2 - 1)
        var height = pow(max(ridged, 0), 1.35) * 0.62

        // The canyon: a meander carved down through everything, deepest at its middle.
        let meander = sin(z * 1.15) * 0.17 + sin(z * 2.7) * 0.05
        let fromRiver = abs(x - meander)
        let cut = 1 - exp(-pow(fromRiver / 0.19, 2.1))
        height *= 0.16 + 0.84 * cut

        // Strata: three beds, not six. Six put a step every few pixels and the
        // silhouettes turned to stairs.
        let beds = 3.0
        let stepped = (height * beds).rounded(.down) / beds
        // A hint of terracing and no more. Treads wide enough to see are treads whose
        // edges run nearly along the line of sight, and those alias into a sawtooth no
        // amount of supersampling removes — the steps belong in the strata colours
        // instead, where they cost nothing.
        height = stepped * 0.12 + height * 0.88

        return height + 0.02
    }

    // MARK: - Yosemite

    /// Domes out of a flat valley floor: a wide U with granite swelling either side.
    private func yosemiteHeight(x: Double, z: Double) -> Double {
        let base = Noise.fbm(x: x * 0.62, y: z * 0.40, octaves: 2)
        var height = pow(base, 1.15) * 0.56

        // The glacial U: flat floor, walls rising steeply at a fixed distance out.
        let fromFloor = abs(x - sin(z * 0.8) * 0.1)
        let valley = min(max((fromFloor - 0.14) / 0.30, 0), 1)
        height *= pow(valley, 0.85)

        // One dome, sheared flat on its near side — Half Dome's whole character.
        let domeX = 0.34
        let domeZ = 1.45
        let toDome = sqrt(pow((x - domeX) / 0.34, 2) + pow((z - domeZ) / 0.46, 2))
        if toDome < 1 {
            let swell = cos(toDome * .pi / 2) * 0.34
            height = max(height, (x > domeX ? swell * 0.22 : swell) + 0.12)
        }

        return height + 0.015
    }
}

extension Scene {
    // MARK: - Acadia

    /// Low granite domes standing out of the Atlantic.
    ///
    /// Nothing here is ridged or terraced. Acadia's rock was ground down under ice and
    /// then drowned at the edges, so the land is a set of rounded swells and the sea
    /// comes into the frame between them — which is the whole reason this park looks
    /// nothing like the other two, and why the icon's stack reads as three different
    /// brochures rather than one printed three times.
    private func acadiaHeight(x: Double, z: Double) -> Double {
        let base = Noise.fbm(x: x * 0.68, y: z * 0.44, octaves: 3)
        // A gentle power curve rather than a ridge: glaciated granite swells.
        var height = pow(base, 1.75) * 0.42

        // Where the coast bites in. A second, slower field decides which ground is
        // land at all, so headlands and inlets alternate down the frame.
        let coast = Noise.fbm(x: x * 0.52 + 11.3, y: z * 0.34 + 4.7, octaves: 2)
        height *= min(max((coast - 0.34) / 0.40, 0), 1)

        // Cadillac: one dome higher than the rest, off to the right.
        let toSummit = sqrt(pow((x - 0.30) / 0.40, 2) + pow((z - 1.25) / 0.60, 2))
        if toSummit < 1 {
            height = max(height, cos(toSummit * .pi / 2) * 0.30 + 0.06)
        }

        return max(height, seaFloor)
    }

    /// Everything at or under this is water.
    private var seaFloor: Double {
        0.062
    }
}

/// Deterministic value noise. No system random anywhere: the icon has to come out
/// byte-identical on every machine that builds it.
enum Noise {
    static func fbm(x: Double, y: Double, octaves: Int) -> Double {
        var total = 0.0
        var amplitude = 0.5
        var frequency = 1.0
        var normalisation = 0.0

        for _ in 0 ..< octaves {
            total += value(x: x * frequency, y: y * frequency) * amplitude
            normalisation += amplitude
            amplitude *= 0.5
            frequency *= 2.07
        }
        return total / normalisation
    }

    private static func value(x: Double, y: Double) -> Double {
        let xi = x.rounded(.down)
        let yi = y.rounded(.down)
        let xf = x - xi
        let yf = y - yi

        // Smoothstep, so the lattice does not show as a grid of creases.
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)

        let a = hash(xi, yi)
        let b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1)
        let d = hash(xi + 1, yi + 1)

        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
    }

    /// A stable fraction in 0..<1 for a column index, used to offset where that column
    /// starts its march. Deterministic, because the icon has to come out byte-identical.
    static func phase(for column: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: column) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 31
        h = h &* 0x7FB5_D329_728E_A185
        h ^= h >> 27
        return Double(h % 10000) / 10000
    }

    private static func hash(_ x: Double, _ y: Double) -> Double {
        var h = UInt64(bitPattern: Int64(x.rounded())) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y.rounded())) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h % 100_000) / 100_000
    }
}
