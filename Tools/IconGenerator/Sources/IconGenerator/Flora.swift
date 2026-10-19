import CoreGraphics
import Foundation

/// The plants, drawn as objects standing on the ground rather than as a tint over it.
///
/// Tinting the ground green says something grows here; it does not say what. A Joshua
/// tree, a bald cypress and a giant sequoia *are* their parks, so they get drawn — as
/// silhouettes with the right posture rather than the right botany.
///
/// They are scattered on a world-space lattice with a hashed offset per cell, so the
/// spacing is irregular and the result is identical on every run. Occlusion is the
/// terrain's job: it records how far away every pixel it paints is, and a plant is drawn
/// only where it stands nearer than that.
struct Grove {
    let scene: Scene
    let projection: (Double, Double) -> CGPoint?

    private var form: LandForm {
        scene.landForm
    }

    /// Every scattered plant.
    func plants(width: Int, height: Int) -> [Plant] {
        guard form.flora != .none, form.floraDensity > 0 else { return [] }

        var found: [Plant] = []
        let spacing = 0.085 / max(form.floraDensity, 0.3)
        var z = 0.10
        while z < 2.6 {
            let reach = z * 1.25 * 0.55
            var x = -reach
            while x < reach {
                let jx = Noise.phase(for: Int((x * 977).rounded()) &+ Int((z * 613).rounded()))
                let jz = Noise.phase(for: Int((x * 331).rounded()) &* 7 &+ Int((z * 97).rounded()))
                let wx = x + (jx - 0.5) * spacing * 1.6
                let wz = z + (jz - 0.5) * spacing * 1.6
                if let plant = plant(atX: wx, z: wz, jitter: jx, width: width, height: height) {
                    found.append(plant)
                }
                x += spacing
            }
            z += spacing * 1.35
        }
        return found
    }

    /// The trees placed by hand, which are the subject rather than the scenery.
    func specimens(width: Int, height: Int) -> [Plant] {
        scene.specimens.compactMap { specimen in
            guard let base = projection(specimen.x, specimen.z),
                  base.x > -Double(width), base.x < Double(width) * 2,
                  base.y > 0, base.y < Double(height) * 4
            else { return nil }
            return Plant(
                kind: specimen.kind,
                base: base,
                height: Double(height) * 0.95 / specimen.z * specimen.height,
                distance: specimen.z,
                jitter: specimen.jitter
            )
        }
    }

    private func plant(
        atX x: Double,
        z: Double,
        jitter: Double,
        width: Int,
        height: Int
    ) -> Plant? {
        let ground = scene.height(x: x, z: z)

        // Where it will and will not grow, which is as much a part of a park as its rock.
        switch form.flora {
        case .cypress, .hammock:
            // Standing in the water or right at its edge.
            guard ground <= form.seaLevel + form.relief * 0.22 else { return nil }
        case .joshua:
            // Off the bare rock: on the flats between the boulder piles.
            guard ground < form.relief * 0.42 else { return nil }
        case .conifer, .giantForest:
            // Below the treeline, off the snow, and out of the sea.
            guard ground < form.relief * min(form.snowLine, 0.80),
                  ground > form.seaLevel + 0.012
            else { return nil }
        case .none:
            return nil
        }

        // Nothing roots on a wall. Without this the firs stood out from Yosemite's
        // granite faces like pins in a cushion.
        let rise = max(
            abs(scene.height(x: x + 0.01, z: z) - ground),
            abs(scene.height(x: x, z: z + 0.01) - ground)
        ) / 0.01
        guard rise < 2.2 else { return nil }

        guard let base = projection(x, z) else { return nil }
        // Range-checked before converting. Close to the camera the projection runs to
        // millions of rows, and `Int(_:)` on that traps rather than saturating.
        guard base.x >= 0, base.x < Double(width),
              base.y >= 0, base.y < Double(height)
        else { return nil }

        let kind: Plant.Kind = switch form.flora {
        case .joshua: .joshua
        case .cypress: .cypress
        case .hammock: .hammock
        // A grove of giant sequoia is not all giant sequoia: white fir and sugar pine
        // stand between them, and the giants read as giants because of it.
        case .giantForest: jitter > 0.82 ? .sequoia : .fir
        case .conifer, .none: .fir
        }

        // Size falls off with distance exactly as the ground does.
        let scale = Double(height) * 0.95 / max(z, 0.08)
        let tall = kind == .sequoia ? 2.1 : 1
        let size = scale * form.floraHeight * tall * (0.78 + jitter * 0.44)
        guard size > 1.5 else { return nil }

        return Plant(kind: kind, base: base, height: size, distance: z, jitter: jitter)
    }
}

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

struct Plant {
    enum Kind {
        /// A spire of drooping courses. Fir, spruce, hemlock.
        case fir
        /// A massive cinnamon column with a rounded, clumped crown.
        case sequoia
        /// Stubby trunk, a few upswept arms, spiked heads. Mojave.
        case joshua
        /// A buttressed foot, a straight bole and a flat, feathery crown.
        case cypress
        /// Rounded clumps of hardwood on a tree island.
        case hammock
    }

    let kind: Kind
    /// Where it stands, in pixels.
    let base: CGPoint
    /// How tall it stands, in pixels.
    let height: Double
    let distance: Double
    let jitter: Double

    /// How far either side of its foot it reaches, in units of its height.
    var reach: Double {
        switch kind {
        case .fir: 0.26
        case .sequoia: 0.36
        case .joshua: 0.36
        case .cypress: 0.32
        case .hammock: 0.98
        }
    }
}

extension LandForm {
    /// How tall this park's plants stand, in world units.
    var floraHeight: Double {
        switch flora {
        case .none: 0
        case .joshua: 0.058
        case .cypress: 0.115
        case .hammock: 0.058
        case .conifer, .giantForest: 0.080
        }
    }
}

// MARK: - Light

/// The colours a plant is painted in, and how they take the light.
///
/// Highlights go towards the land's own sun rather than towards white, so a tree at noon
/// is lit warm and a tree at night is lit by the moon.
struct PlantInks {
    let canopy: Ink
    let bark: Ink
    /// Cinnamon, for the one tree whose bark is the thing you remember about it.
    let sequoiaBark: Ink
    let light: Ink

    init(land: Land) {
        canopy = land.vegetation.darkened(0.06)
        bark = land.vegetation.darkened(0.45).mixed(with: Ink(hex: 0x5A4A3A), amount: 0.35)
        sequoiaBark = land.bark ?? bark
        light = land.sun
    }

    /// `amount` runs from -1, facing away from the light, to 1, facing straight into it.
    func lit(_ ink: Ink, _ amount: Double) -> Ink {
        amount > 0
            ? ink.mixed(with: light, amount: min(amount, 1) * 0.26)
            : ink.darkened(min(-amount, 1) * 0.34)
    }
}

// MARK: - Silhouettes

extension Plant {
    /// The colour at a point on the plant, or nil off it. `u` runs across in units of
    /// the plant's height, positive to the right; `v` up from its foot, 0 to 1.
    func ink(u screenU: Double, v: Double, inks: PlantInks) -> Ink? {
        guard v > -0.01, v < 1.01 else { return nil }
        // Half of them are mirrored, so neighbours do not all lean the same way. The
        // light is not: it comes from the left whichever way the tree faces, so every
        // shading term below is put back into screen space with `flip`.
        let flip: Double = jitter > 0.5 ? -1 : 1
        let u = screenU * flip

        switch kind {
        case .fir: return fir(u, v, flip: flip, inks: inks)
        case .sequoia: return sequoia(u, v, flip: flip, inks: inks)
        case .joshua: return joshua(u, v, flip: flip, inks: inks)
        case .cypress: return cypress(u, v, flip: flip, inks: inks)
        case .hammock: return hammock(u, v, flip: flip, inks: inks)
        }
    }

    private func fir(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        let along = u - (jitter - 0.5) * 0.05 * v
        if v < 0.16, abs(along) < 0.026 {
            return inks.lit(inks.bark, -along * flip / 0.026 * 0.6)
        }
        guard v >= 0.10 else { return nil }

        // Courses, each wide at its foot and drawn in towards the next: the drooping
        // skirt of a fir's branches, which is what makes it a fir and not a cone.
        let t = (v - 0.10) / 0.90
        let courses = 5 + (jitter * 2).rounded(.down)
        let position = t * courses
        let course = position - position.rounded(.down)
        let envelope = 0.22 * pow(1 - t, 0.92) + 0.012
        let half = envelope * (0.56 + 0.44 * (1 - course))
        guard abs(along) < half else { return nil }

        let across = along * flip / half
        let light = -across * 0.55 + (course - 0.5) * 0.45 - (course < 0.16 ? 0.38 : 0)
        return inks.lit(inks.canopy, light)
    }

    private func sequoia(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        // The crown: one dense mass over the top of the trunk, with clumps standing
        // out from it on the ends of the big limbs. Drawn as separate puffs on sticks,
        // it was a lollipop — and a lollipop is the one thing a giant sequoia is not.
        let clumps: [(Double, Double, Double, Double)] = [
            (0.00, 0.80, 0.155, 0.210),
            (-0.165, 0.640, 0.100, 0.060), (0.170, 0.710, 0.105, 0.062),
            (-0.160, 0.810, 0.090, 0.055), (0.145, 0.880, 0.085, 0.052),
        ]
        for (index, clump) in clumps.enumerated() {
            let shift = (Noise.phase(for: index &* 31 &+ Int(jitter * 1000)) - 0.5) * 0.04
            if let light = lump(u, v, clump, shift: shift, seed: index, flip: flip) {
                return inks.lit(inks.canopy, light)
            }
        }

        // Stout limbs out to the clumps, rising as they go.
        for (index, clump) in clumps.dropFirst().enumerated() {
            let shift = (Noise.phase(for: (index + 1) &* 31 &+ Int(jitter * 1000)) - 0.5) * 0.04
            let reach = (clump.0 + shift) * 0.80
            if let along = limb(u, v, from: (0, clump.1 - 0.05), to: (reach, clump.1), 0.010) {
                return inks.lit(inks.sequoiaBark.darkened(0.20), -along * flip * 0.6)
            }
        }

        // The trunk: a buttressed foot, then a column that barely tapers, which is the
        // whole silhouette of the tree. Most of what a giant sequoia looks like is that
        // it does not get narrower.
        guard v < 0.97 else { return nil }
        let half = 0.064 * (1 + 0.9 * exp(-v * 16)) * (1 - 0.48 * v)
        guard abs(u) < half else { return nil }
        let across = u * flip / half
        // Round, so lit down the left and falling into shadow round the right.
        var light = -across * 0.85 + 0.05
        // Deep vertical furrows in the bark.
        let furrow = abs(sin(across * 4.6 + jitter * 11))
        light -= max(0.28 - furrow, 0) * 1.6
        // Fire scars at the foot, which nearly every old one carries.
        if v < 0.10, across > 0.15 {
            light -= 0.55 * (1 - v / 0.10)
        }
        return inks.lit(inks.sequoiaBark, light)
    }

    private func joshua(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        // Spiked heads at the end of every arm.
        let heads: [(Double, Double, Double)] = [
            (-0.235, 0.835, 0.088), (0.215, 0.775, 0.082), (0.03, 0.925, 0.078),
        ]
        for (index, head) in heads.enumerated() {
            let dx = u - head.0
            // Swept up: the leaves point skywards, so a head is taller than wide.
            let dy = (v - head.1) / 1.15
            let angle = atan2(dy, dx)
            // Many narrow blades of uneven length. A few regular round-ended lobes
            // made a daisy; a Joshua tree's head is a ragged ball of daggers.
            let blade = pow(abs(cos(angle * 8.5 + Double(index) * 2.3)), 2.2)
            let length = 0.75 + 0.5 * Noise.phase(for: Int((angle + 4) * 9) &+ index &* 17)
            let radius = head.2 * (0.42 + 0.62 * blade * length)
            if dx * dx + dy * dy < radius * radius {
                return inks.lit(inks.canopy, -dx * flip / head.2 * 0.5 + dy / head.2 * 0.6)
            }
        }
        let limbs: [((Double, Double), (Double, Double), Double)] = [
            ((0.00, 0.00), (0.02, 0.55), 0.050),
            ((0.01, 0.42), (-0.15, 0.60), 0.036), ((-0.15, 0.60), (-0.23, 0.79), 0.032),
            ((0.02, 0.48), (0.16, 0.58), 0.034), ((0.16, 0.58), (0.21, 0.73), 0.030),
            ((0.02, 0.54), (0.03, 0.87), 0.032),
        ]
        for limb in limbs {
            if let along = self.limb(u, v, from: limb.0, to: limb.1, limb.2) {
                return inks.lit(inks.bark, -along * flip * 0.6)
            }
        }
        return nil
    }

    private func cypress(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        let crown: [(Double, Double, Double, Double)] = [
            (-0.13, 0.80, 0.14, 0.068), (0.11, 0.85, 0.14, 0.068), (0.00, 0.92, 0.13, 0.058),
            (-0.04, 0.73, 0.10, 0.050), (0.15, 0.745, 0.085, 0.045),
        ]
        for (index, clump) in crown.enumerated() {
            if let light = lump(u, v, clump, shift: 0, seed: index, flip: flip) {
                return inks.lit(inks.canopy, light)
            }
        }
        // Knees: the cypress's own roots standing up out of the water round its foot.
        for knee in [-0.21, -0.13, 0.15, 0.24] {
            let rise = 0.052 * (1 - abs(u - knee) / 0.022)
            if v < rise {
                return inks.lit(inks.bark, -(u - knee) * flip / 0.022 * 0.5)
            }
        }
        guard v < 0.90 else { return nil }
        let half = 0.026 + 0.105 * exp(-v * 10)
        guard abs(u) < half else { return nil }
        return inks.lit(inks.bark, -u * flip / half * 0.7)
    }

    private func hammock(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        let clumps: [(Double, Double, Double, Double)] = [
            (-0.32, 0.40, 0.34, 0.32), (0.04, 0.58, 0.40, 0.40),
            (0.40, 0.38, 0.32, 0.30), (-0.02, 0.24, 0.62, 0.24),
        ]
        for (index, clump) in clumps.enumerated() {
            if let light = lump(u, v, clump, shift: 0, seed: index, flip: flip) {
                return inks.lit(inks.canopy, light)
            }
        }
        return nil
    }

    // MARK: Primitives

    /// A clump of foliage, lit from the upper left. Returns how much it faces the
    /// light, or nil off it.
    ///
    /// The edge and the inside both come from noise. A regular scalloped edge with an
    /// even fill is a cloud from a children's book; foliage is masses of leaf with
    /// gaps and shadow between them, ragged at the edge.
    private func lump(
        _ u: Double,
        _ v: Double,
        _ clump: (Double, Double, Double, Double),
        shift: Double,
        seed: Int,
        flip: Double
    ) -> Double? {
        let dx = (u - clump.0 - shift) / clump.2
        let dy = (v - clump.1) / clump.3
        let reach = dx * dx + dy * dy
        guard reach < 1 else { return nil }
        let offset = Double(seed) * 7.13 + jitter * 13.7
        let ragged = Noise.fbm(x: dx * 2.4 + offset, y: dy * 2.4 - offset, octaves: 3)
        let edge = 0.60 + 0.58 * ragged
        guard reach < edge * edge else { return nil }
        let mottle = Noise.fbm(x: dx * 6.5 - offset, y: dy * 6.5 + offset, octaves: 2) - 0.5
        return -dx * flip * 0.50 + dy * 0.65 - 0.05 + mottle * 1.1
    }

    /// A limb: a segment with a radius. Returns where across it the point lies, -1 to 1,
    /// or nil off it.
    private func limb(
        _ u: Double,
        _ v: Double,
        from start: (Double, Double),
        to end: (Double, Double),
        _ radius: Double
    ) -> Double? {
        let ex = end.0 - start.0
        let ey = end.1 - start.1
        let length = ex * ex + ey * ey
        let t = length > 0 ? min(max(((u - start.0) * ex + (v - start.1) * ey) / length, 0), 1) : 0
        let dx = u - (start.0 + ex * t)
        let dy = v - (start.1 + ey * t)
        guard dx * dx + dy * dy < radius * radius else { return nil }
        return dx / radius
    }
}
