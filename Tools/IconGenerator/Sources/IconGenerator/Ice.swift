import Foundation

extension Plant {
    /// A berg afloat: wide and low, its top broken into a few tilted facets, white where
    /// it faces the light and the water's own blue where it does not.
    ///
    /// Drawn as a plant because it is the same kind of thing to the renderer: an object
    /// standing on the surface, scattered over it, sized by distance and hidden by
    /// whatever stands in front of it.
    func floe(_ u: Double, _ v: Double, flip: Double, inks: PlantInks) -> Ink? {
        guard v >= 0, abs(u) < 0.9 else { return nil }
        // The outline: a low mound broken by noise into a few blocks of uneven height,
        // because ice breaks along cracks rather than wearing round.
        let across = abs(u) / 0.9
        let blocks = Noise.fbm(x: u * 3.2 + jitter * 17, y: jitter * 5, octaves: 2)
        let top = 0.42 * pow(1 - across, 0.5) * (0.55 + blocks * 0.9)
        guard v < top else { return nil }
        // Faceted: the light turns on which way each block's top leans, not on a smooth
        // curve, so the berg comes out as broken planes.
        let facet = (Noise.fbm(x: u * 5 + jitter * 3, y: 1.7, octaves: 1) - 0.5) * 2.4
        let side = -u * flip * 1.6 + facet
        let face = side > -0.15 ? inks.ice : inks.iceShadow
        // The waterline: darker at the foot, where the ice is wet and melting.
        let wet = v < top * 0.18 ? 0.25 : 0
        return inks.lit(face, min(max(side, -1), 1) * 0.35 - wet)
    }
}
