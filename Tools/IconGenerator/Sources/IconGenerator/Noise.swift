import Foundation

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

    /// Ridged noise folded per octave rather than once over the sum. See
    /// `LandForm.Crest.peaks` for why that is the difference between a range and a mesa.
    static func peaks(x: Double, y: Double, octaves: Int) -> Double {
        var total = 0.0
        var amplitude = 0.5
        var frequency = 1.0
        var normalisation = 0.0

        for _ in 0 ..< octaves {
            let fold = 1 - abs(value(x: x * frequency, y: y * frequency) * 2 - 1)
            total += fold * amplitude
            normalisation += amplitude
            amplitude *= 0.5
            frequency *= 2.07
        }
        return total / normalisation
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

    private static func hash(_ x: Double, _ y: Double) -> Double {
        var h = UInt64(bitPattern: Int64(x.rounded())) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(y.rounded())) &* 0xC2B2_AE3D_27D4_EB4F
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h % 100_000) / 100_000
    }
}
