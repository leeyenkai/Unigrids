import Foundation

/// A small, fixed PRNG whose output depends only on its seed.
///
/// `SystemRandomNumberGenerator` is not reproducible and `Int.random` changes between
/// runs, which would make a stamp impression shift every time the passport page is drawn.
/// This is splitmix64: short, well distributed, and identical on every platform and every
/// OS release, which is what "the impression looks the same every time" requires.
public struct DeterministicRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which splitmix64 handles but which makes the first
        // few outputs needlessly correlated across nearby seeds.
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `range`, drawn deterministically.
    public mutating func double(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
