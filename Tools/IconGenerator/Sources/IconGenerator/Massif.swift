import Foundation

extension LandForm {
    /// A mountain wall set out by its own skyline: a crest line given point by point, and
    /// flanks falling away from it in front and behind.
    ///
    /// For a mountain known by its outline and nothing else: Aoraki's long summit ridge,
    /// the Ten Peaks standing in a row over Moraine Lake, the crenellated top of Cradle
    /// Mountain. Noise makes a range, and every range it makes is a different one; a
    /// landmark is a curve of one variable, so it has the same outline from every bearing
    /// and only one summit. Neither can draw a particular skyline, and for these three the
    /// skyline is what the eye checks first.
    ///
    /// The crest is joined point to point by straight runs, so a summit is a point and a
    /// col is a notch, and then broken by noise finer than the points so no run is a
    /// ruled line. The faces below it are cut by gullies that run straight down them,
    /// which is what gives the light something to catch: a smooth face reads as a
    /// cardboard cut-out of a mountain, however right its outline.
    struct Massif {
        /// One point on the crest: across, out from the camera, and how high.
        struct Point {
            let x: Double
            let z: Double
            let height: Double
        }

        /// Left to right. The first and last should be low, or the wall ends in a cliff
        /// at either side of the frame.
        let crest: [Point]
        /// How far the flanks run out from the crest, in front and behind, before they
        /// meet the ground.
        let depth: Double
        /// The exponent on the flanks' fall. Above 1 is concave: steep under the crest
        /// and flaring into a broad apron at the foot, which is how scree and moraine lie.
        var flank = 1.5
        /// The share of the height that stands as a sheer crown along the crest, above
        /// the flanks. Zero for none. Dolerite does this — columns standing on their own
        /// talus — and nothing else here does.
        var cliff = 0.0
        /// How deep the gullies are cut, as a share of the height, and how many there are
        /// to a unit across.
        var gullies = 0.0
        var gullyScale = 6.0
        /// How far the noise breaks the crest up and down, in units of height.
        var jag = 0.0
        /// How far buttresses stand out from the face and gullies cut back into it, as a
        /// share of `depth`. Zero leaves the face a straight wall square to the camera,
        /// which takes the light the same all the way along and reads as a backdrop: a
        /// spur has a side to the sun and a side away from it.
        var spurs = 0.0

        /// The highest point on the crest.
        private var summit: Double {
            crest.map(\.height).max() ?? 1
        }

        /// Height of the wall at a point; zero off it.
        func height(x: Double, z: Double) -> Double {
            guard let first = crest.first, let last = crest.last,
                  x > first.x, x < last.x,
                  let index = crest.lastIndex(where: { $0.x <= x }),
                  index + 1 < crest.count
            else { return 0 }
            let left = crest[index]
            let right = crest[index + 1]
            let t = (x - left.x) / (right.x - left.x)
            let ridge = left.z + (right.z - left.z) * t
            let buttress = Noise.fbm(x: x * 3.3, y: 7.1, octaves: 2) - 0.5
            let across = abs(z - ridge) / (depth * (1 + spurs * buttress * 2))
            guard across < 1 else { return 0 }

            let top = left.height + (right.height - left.height) * t

            var rise = pow(1 - across, flank)
            if cliff > 0 {
                // A crown standing straight up off the top of the flanks. Stepped over a
                // few hundredths rather than cut dead, so the renderer, which takes its
                // light from the slope, finds a wall rather than a discontinuity. Only
                // as tall as the summits are high: carried along the whole crest at one
                // height, it ran out to the edge of the frame as a low wall.
                let crown = cliff * pow(top / summit, 3)
                let s = min(max((across - 0.07) / 0.035, 0), 1)
                rise = (1 - crown) * rise + crown * (1 - s * s * (3 - 2 * s))
            }
            if gullies > 0 {
                // Keyed almost entirely on `x`, so each one runs straight down the face
                // from the crest; faded in below the crest, so the skyline itself keeps
                // the outline it was given.
                // Folded, so the ribs between them come out sharp and the gullies broad:
                // smooth noise left the face looking draped rather than cut.
                let grain = Noise.fbm(x: x * gullyScale, y: z * gullyScale * 0.22, octaves: 3)
                let groove = 1 - abs(grain * 2 - 1)
                let fade = min(across / 0.10, 1)
                rise *= 1 - gullies * fade * (1 - groove)
            }
            // The crest broken up, and only the crest. Added to the height at the top
            // and carried all the way down, it put a stripe under every notch in the
            // skyline and the face came out ruled from top to bottom like a curtain.
            let broken = (Noise.fbm(x: x * 13, y: ridge * 3.1, octaves: 3) - 0.5) * jag
            return max(top, 0) * rise + broken * pow(rise, 6)
        }
    }
}
