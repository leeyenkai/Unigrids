import Foundation

/// One tree placed by hand, in world units.
struct Specimen {
    let x: Double
    let z: Double
    let height: Double
    let kind: Plant.Kind
    let jitter: Double
}

extension Scene {
    /// The trees that are the subject of the park rather than its scenery.
    var specimens: [Specimen] {
        switch self {
        case .sequoia:
            // Two trunks framing the stack, close enough that their crowns are out of
            // the frame and all that shows is bark — which is how a giant sequoia is
            // actually seen, from its foot, craning up. Two more further off with their
            // crowns in view, so the eye has the whole tree as well as its scale.
            [
                Specimen(x: -0.205, z: 0.40, height: 0.92, kind: .sequoia, jitter: 0.21),
                Specimen(x: 0.235, z: 0.52, height: 0.98, kind: .sequoia, jitter: 0.64),
                Specimen(x: -0.30, z: 1.05, height: 0.86, kind: .sequoia, jitter: 0.83),
                Specimen(x: 0.30, z: 1.30, height: 0.80, kind: .sequoia, jitter: 0.37),
            ]
        case .joshuaTree:
            // The trees the park is named for, where the stack does not cover them:
            // one large on the right edge, one with its arms up over the brochures on
            // the left, and two smaller out on the flats between them.
            [
                Specimen(x: 0.30, z: 0.60, height: 0.30, kind: .joshua, jitter: 0.12),
                Specimen(x: -0.40, z: 0.85, height: 0.32, kind: .joshua, jitter: 0.71),
                Specimen(x: 0.05, z: 1.60, height: 0.22, kind: .joshua, jitter: 0.33),
                Specimen(x: -0.33, z: 1.95, height: 0.20, kind: .joshua, jitter: 0.88),
            ]
        default:
            []
        }
    }
}
