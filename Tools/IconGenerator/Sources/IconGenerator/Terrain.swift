import CoreGraphics
import Foundation

/// A heightfield rendered in perspective, the way a flight simulator draws one.
///
/// The previous landscape was a stack of flat silhouettes, and no amount of shading fixed
/// it: layered cut-outs have no perspective, so nothing converges, nearer ground is no
/// larger than far ground, and a ridge never hides a shoulder of itself. This renders an
/// actual surface instead.
///
/// The method is the classic voxel-space one. March away from the camera, column by
/// column; project each sample's height to a screen row; and keep a y-buffer per column
/// so nearer ground paints over whatever is behind it. That gives true occlusion and true
/// convergence for a few million cheap operations — no 3D framework, and deterministic to
/// the byte, which a GPU path would not be.
struct Terrain {
    let scene: Scene
    let land: Land

    // MARK: - Camera

    //
    // Low and tilted down a little, the way you end up looking at a valley after
    // dragging the globe around: enough height to see the far wall over the near one,
    // not so much that it flattens into a map.

    private let horizon = 0.325
    private let cameraHeight = 0.55
    private let focal = 0.95
    private let near = 0.055
    private let far = 3.4
    /// How wide the view spreads with distance. This is the whole reason the thing reads
    /// as three-dimensional: ground a long way off covers fewer pixels per metre.
    private let spread = 1.25

    func render(size: Int) -> CGImage? {
        let width = size
        let height = size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        paintSky(into: &pixels, width: width, height: height)

        // The lowest row already painted for each column. Marching near to far and only
        // drawing above it gives occlusion for free.
        var ceiling = [Int](repeating: height, count: width)

        // A fixed fraction of a step, different for every column.
        //
        // Every column marches the same ladder of distances, so a boundary that runs
        // nearly level crosses the same rung for a run of columns and then drops to the
        // next: a regular staircase, and regularity is the thing the eye picks out. A
        // column that starts a fraction of a step along samples a different ladder, and
        // the boundary frays instead of stepping. The same total work, and the result
        // resolves under the 4x downsample into a smooth edge.
        let phase = (0 ..< width).map { Noise.phase(for: $0) }
        // The sample that last painted each column, and how hazy it was. A span is
        // shaded by interpolating from it to the current one, so nothing that feeds a
        // pixel's colour is constant across a span.
        var trailing = [(sample: Sample, fog: Double)?](repeating: nil, count: width)

        var z = near
        // Steps grow with distance: far ground needs fewer samples because it covers
        // fewer rows, and uniform stepping spends most of its time on invisible detail.
        while z < far {
            // Fine enough that a span is about a row tall. That matters for more than
            // the silhouette: the slope, the vegetation and the haze are all properties
            // of a *sample*, so anything constant across a span shows as a band, and
            // the bands stair where the span edges shift between columns. Interpolating
            // across a span softens that; making the span a row deep removes it.
            let step = 0.0005 + z * 0.0008

            for x in 0 ..< width {
                // Each column marches its own ladder, offset by a fixed fraction of a
                // step. Haze and the row scale follow that distance too, or the colour
                // and the geometry disagree by a fraction of a row.
                let depth = z + phase[x] * step
                let rowScale = focal / depth
                // Haze builds with distance, but slowly: ramped too fast it bleaches
                // the near wall along with the far one and the valley goes to cream.
                let fog = pow(min(max((depth - near) / (far * 0.92), 0), 1), 1.45)
                let worldX = (Double(x) / Double(width) - 0.5) * depth * spread
                let sample = surface(x: worldX, z: depth)
                let screenY = (horizon + (cameraHeight - sample.height) * rowScale)
                    * Double(height)
                let exact = max(screenY, 0)
                let top = Int(exact)
                guard top < ceiling[x] else { continue }

                // The skyline lands between two rows far more often than on one, and
                // rounding it to the nearer is exactly what put a staircase along every
                // curve. The row it lands in gets painted in proportion to how much of
                // it the rock actually covers.
                blend(
                    column: x, row: top,
                    with: shade(height: sample.height, sample: sample, fog: fog),
                    coverage: 1 - (exact - Double(top)),
                    into: &pixels, width: width
                )
                // Through the old boundary row, not up to it. That row was painted at
                // partial coverage when it was the skyline; left as it was, every one
                // of them survives as a pale line and the face comes out banded.
                //
                // **Every row in the span is shaded for its own altitude**, recovered by
                // inverting the projection at this distance. Shading the span from one
                // sample and filling — or even grading between two samples — makes a
                // strata boundary land at the span's edge rather than at the row where
                // the altitude actually crosses it. The span edges differ column by
                // column, so the boundary comes out as a staircase. This is the fix for
                // that, and it is the only one that works: the colour has to be a
                // function of the row, because the boundary is.
                let solidTo = min(ceiling[x] + 1, height)
                let span = Double(solidTo - top)
                for y in (top + 1) ..< solidTo {
                    let rowHeight = cameraHeight
                        - (Double(y) / Double(height) - horizon) / rowScale
                    var rowSample = sample
                    var rowFog = fog
                    if let behind = trailing[x] {
                        let t = Double(y - top) / span
                        rowSample = Sample(
                            height: rowHeight,
                            lit: sample.lit + (behind.sample.lit - sample.lit) * t,
                            green: sample.green + (behind.sample.green - sample.green) * t
                        )
                        rowFog = fog + (behind.fog - fog) * t
                    }
                    fill(
                        column: x, row: y,
                        with: shade(height: rowHeight, sample: rowSample, fog: rowFog),
                        into: &pixels, width: width
                    )
                }
                ceiling[x] = top
                trailing[x] = (sample, fog)
            }
            z += step
        }

        return makeImage(from: &pixels, width: width, height: height)
    }

    // MARK: - The surface

    private struct Sample {
        let height: Double
        /// How steeply the ground falls away towards the light, in -1...1.
        let lit: Double
        /// How thickly the ground is vegetated, 0...1. Zion's floor is cottonwood and
        /// its ledges carry scrub wherever they hold water, and that green is most of
        /// the colour in the park that is not rock.
        let green: Double
    }

    /// Height and lighting at one point, with the slope taken from a finite difference
    /// across the step the renderer is actually walking.
    private func surface(x: Double, z: Double) -> Sample {
        let delta = 0.012
        let here = scene.height(x: x, z: z)
        let alongX = scene.height(x: x + delta, z: z)
        let alongZ = scene.height(x: x, z: z + delta)

        // Light from the upper left, raking across the valley.
        let slopeX = (here - alongX) / delta
        let slopeZ = (here - alongZ) / delta
        let lit = (slopeX * 0.78 + slopeZ * 0.34) / sqrt(1 + slopeX * slopeX + slopeZ * slopeZ)

        // Low ground, and the gentler of the slopes above it: plants need somewhere to
        // sit and something to drink, so a sheer face stays bare however low it is.
        // Up the lower slopes, not just along the floor: in the park itself the scrub
        // climbs every bench and talus fan that will hold it, and a green confined to
        // the riverbed is a green the icon never shows, because the brochures lie over
        // exactly that part of the frame.
        let lowland = 1 - min(max((here - 0.05) / 0.46, 0), 1)
        // Only a genuinely sheer face stays bare. Penalising slope harder than this
        // wipes the green off the canyon walls entirely — and the walls are the part of
        // the frame the brochures do not cover, so it is the only green anyone sees.
        let bare = min(abs(slopeX) * 0.16, 1)
        let patch = Noise.fbm(x: x * 4.1, y: z * 2.6, octaves: 2)
        // Thresholded into patches rather than dialled in as a wash. Green blended at
        // half strength over orange rock is olive, and olive is mud: vegetation reads
        // as vegetation only where it is allowed to be the colour it actually is.
        let raw = lowland * (1 - bare) * (patch * 2.1 - 0.38)
        let t = min(max((raw - 0.30) / 0.22, 0), 1)
        let green = t * t * (3 - 2 * t)

        return Sample(height: here, lit: lit, green: green)
    }

    /// Rock colour by altitude, shaded by slope, then pushed into the haze by distance.
    private func shade(height: Double, sample: Sample, fog: Double) -> Ink {
        // Water first: at or below the waterline there is no rock to shade, and the
        // sea takes its own colour whatever the slope underneath it is doing.
        if land.seaLevel > 0, height <= land.seaLevel + 0.0004 {
            let glint = max(sample.lit, 0) * 0.16
            return land.sea.lightened(glint).mixed(with: land.haze, amount: fog * 0.58)
        }

        let beds = land.ridges
        // Bowed towards the dark beds: mapped straight, most of the visible surface
        // sits in the pale upper strata and the whole canyon goes to cream. The white
        // caps belong on the rims only, which is where they are in the rock.
        let altitude = pow(min(max(height / 0.80, 0), 0.999), 1.35)
        let position = altitude * Double(beds.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, beds.count - 1)
        // Crisp at the bed boundary, blended across the rest of it. A bed in sandstone
        // has an edge — that is what makes it a bed — and blending every band into the
        // next was what left the walls reading as dunes. The interest comes from the
        // colour here rather than from the geometry, which is the point: the form stays
        // simple and the rock still looks like rock.
        // Smoothly interpolated across the whole bed, not sharpened at its boundary.
        //
        // A crisp bed edge looks right in isolation and is the thing that put a
        // staircase along every near-horizontal boundary in the frame. Each row gets
        // one colour, so a transition that resolves in less than a row has to land on
        // a row edge; adjacent columns put it on different rows, and that is the
        // stair. Spread across the bed it always spans several rows and comes out as a
        // gradient. The rock gets its definition from the colours and the light
        // instead, which cannot alias because neither has an edge.
        let blend = position - Double(lower)

        var ink = beds[beds.count - 1 - upper].mixed(
            with: beds[beds.count - 1 - lower], amount: 1 - blend
        )
        // Continuous, not quantised. Flat steps of light were a deliberate choice —
        // they keep the form and drop the texture — but `lit` comes from the surface
        // normal at the sample, so it is constant for a whole span, and a quantised
        // value that is constant for a span puts its boundary on the span's edge. The
        // spans are the march's, not the shape's, so the boundary came out as a
        // staircase with a tread per step. The simplicity has to come from the shape
        // being simple, which it now is, rather than from posterising the light.
        let shade = sample.lit
        ink = shade > 0
            ? ink.lightened(shade * 0.30)
            : ink.darkened(-shade * 0.50)

        ink = ink.mixed(with: land.vegetation, amount: sample.green * 0.96)
        return ink.mixed(with: land.haze, amount: fog * 0.58)
    }

    // MARK: - Pixels

    private func fill(
        column x: Int,
        row y: Int,
        with ink: Ink,
        into pixels: inout [UInt8],
        width: Int
    ) {
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8(ink.red * 255)
        pixels[offset + 1] = UInt8(ink.green * 255)
        pixels[offset + 2] = UInt8(ink.blue * 255)
        pixels[offset + 3] = 255
    }

    /// Paints one row at partial coverage, over whatever is already there.
    private func blend(
        column x: Int,
        row y: Int,
        with ink: Ink,
        coverage: Double,
        into pixels: inout [UInt8],
        width: Int
    ) {
        let alpha = min(max(coverage, 0), 1)
        guard alpha > 0.002 else { return }
        let offset = (y * width + x) * 4
        func mix(_ existing: UInt8, _ incoming: CGFloat) -> UInt8 {
            let under = Double(existing) / 255
            return UInt8(min(max((under + (Double(incoming) - under) * alpha) * 255, 0), 255))
        }
        pixels[offset] = mix(pixels[offset], ink.red)
        pixels[offset + 1] = mix(pixels[offset + 1], ink.green)
        pixels[offset + 2] = mix(pixels[offset + 2], ink.blue)
        pixels[offset + 3] = 255
    }

    private func paintSky(into pixels: inout [UInt8], width: Int, height: Int) {
        let skyDepth = Double(height) * (horizon + 0.10)

        for y in 0 ..< height {
            let t = min(max(Double(y) / skyDepth, 0), 1)
            let base = land.sky.mixed(with: land.skyHorizon, amount: pow(t, 0.80))

            // Cloud thins to nothing at the horizon and at the very top of the frame.
            let band = sin(min(t, 1) * .pi) * (1 - t * 0.35)

            for x in 0 ..< width {
                var ink = base
                if band > 0.04 {
                    let cloud = Noise.fbm(
                        x: Double(x) / Double(width) * 3.1,
                        y: Double(y) / Double(height) * 7.4,
                        octaves: 3
                    )
                    let cover = max(cloud - 0.52, 0) / 0.48 * band
                    ink = ink.mixed(with: land.cloud, amount: min(cover * 1.25, 0.92))
                }
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(ink.red * 255)
                pixels[offset + 1] = UInt8(ink.green * 255)
                pixels[offset + 2] = UInt8(ink.blue * 255)
                pixels[offset + 3] = 255
            }
        }
    }

    private func makeImage(from pixels: inout [UInt8], width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
