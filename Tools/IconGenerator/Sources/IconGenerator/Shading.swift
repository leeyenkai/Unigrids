import CoreGraphics

/// The material layer: gradients, shadows and the light the mark is lit by.
///
/// An earlier version of this icon was flat polygons with hard edges, on the principle
/// that a Unigrid brochure is printed and printed things do not glow. That principle is
/// right for the guides inside the app and wrong here. Every icon in the system's own set
/// is a lit object — gradients across its faces, a soft shadow under it, a highlight where
/// the light catches — and an icon that refuses all three does not read as austere beside
/// them, it reads as unfinished.
enum Light {
    /// Where the light comes from. Top-left, as it does in every icon Apple ships, so
    /// the mark sits with the rest of the dock rather than arguing with it.
    static let direction = CGVector(dx: -0.38, dy: -0.92)

    /// How far a face's own shading swings either side of its base colour.
    static let faceRange = 0.12
}

extension Ink {
    /// The same ink lifted towards white, for the lit edge of a face.
    func lightened(_ amount: Double) -> Ink {
        Ink(
            red: red + (1 - red) * amount,
            green: green + (1 - green) * amount,
            blue: blue + (1 - blue) * amount
        )
    }

    /// The same ink taken towards black, for the shaded edge.
    func darkened(_ amount: Double) -> Ink {
        Ink(red: red * (1 - amount), green: green * (1 - amount), blue: blue * (1 - amount))
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension CGContext {
    /// Fills a path with a linear gradient running along the light's direction.
    ///
    /// The gradient is subtle on purpose: a face is one material catching the light
    /// unevenly, not two colours blended. Wide swings read as plastic.
    func fill(_ path: CGPath, with ink: Ink, sweep: Double = Light.faceRange) {
        let box = path.boundingBoxOfPath
        guard box.width > 0, box.height > 0 else { return }

        saveGState()
        addPath(path)
        clip()

        let start = CGPoint(
            x: box.midX - Light.direction.dx * box.width * 0.5,
            y: box.midY - Light.direction.dy * box.height * 0.5
        )
        let end = CGPoint(
            x: box.midX + Light.direction.dx * box.width * 0.5,
            y: box.midY + Light.direction.dy * box.height * 0.5
        )
        drawGradient(
            from: ink.lightened(sweep),
            to: ink.darkened(sweep * 0.72),
            start: start,
            end: end
        )
        restoreGState()
    }

    /// Fills a path with a gradient straight down, for sky and ground where the light
    /// is overhead rather than raking.
    func fillVertical(_ path: CGPath, top: Ink, bottom: Ink) {
        let box = path.boundingBoxOfPath
        guard box.height > 0 else { return }
        saveGState()
        addPath(path)
        clip()
        drawGradient(
            from: top, to: bottom,
            start: CGPoint(x: box.midX, y: box.minY),
            end: CGPoint(x: box.midX, y: box.maxY)
        )
        restoreGState()
    }

    /// A flat fill, for the few places that genuinely want one.
    func fillFlat(_ path: CGPath, _ ink: Ink) {
        addPath(path)
        setFillColor(ink.cgColor())
        fillPath()
    }

    /// Runs `body` with a soft shadow set, then clears it.
    ///
    /// Offset down and slightly right, opposite the light. The blur is generous relative
    /// to the offset, which is what makes an object look like it is resting on something
    /// rather than pasted over it.
    func withShadow(
        offsetY: Double,
        blur: Double,
        alpha: CGFloat,
        scale: Double,
        _ body: () -> Void
    ) {
        saveGState()
        setShadow(
            offset: CGSize(width: offsetY * scale * 0.22, height: offsetY * scale),
            blur: CGFloat(blur * scale),
            color: CGColor(srgbRed: 0.05, green: 0.04, blue: 0.03, alpha: alpha)
        )
        body()
        restoreGState()
    }

    private func drawGradient(from: Ink, to: Ink, start: CGPoint, end: CGPoint) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                  colorsSpace: space,
                  colors: [from.cgColor(), to.cgColor()] as CFArray,
                  locations: [0, 1]
              )
        else { return }
        drawLinearGradient(
            gradient, start: start, end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}

extension CGContext {
    /// A low sun as a soft radial bloom. No disc: a drawn sun is the fastest way to make
    /// a landscape look like clip-art, and the light it throws is the point anyway.
    func sunGlow(at centre: CGPoint, radius: CGFloat, ink: Ink) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let gradient = CGGradient(
                  colorsSpace: space,
                  colors: [ink.cgColor(alpha: 0.85), ink.cgColor(alpha: 0)] as CFArray,
                  locations: [0, 1]
              )
        else { return }
        drawRadialGradient(
            gradient,
            startCenter: centre, startRadius: 0,
            endCenter: centre, endRadius: radius,
            options: []
        )
    }
}

extension Ink {
    /// A blend towards another ink: `amount` 0 is self, 1 is the other.
    func mixed(with other: Ink, amount: Double) -> Ink {
        let t = min(max(amount, 0), 1)
        return Ink(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    /// The same ink at reduced opacity, for marks that are texture rather than content.
    func withAlpha(_ alpha: CGFloat) -> (ink: Ink, alpha: CGFloat) {
        (self, alpha)
    }
}

extension CGContext {
    /// A flat fill at partial opacity.
    func fillFlat(_ path: CGPath, _ value: (ink: Ink, alpha: CGFloat)) {
        addPath(path)
        setFillColor(value.ink.cgColor(alpha: value.alpha))
        fillPath()
    }

    /// Lays a wash of the air's own colour over everything drawn so far.
    ///
    /// Called between terrain layers, so each step further back has had more washes over
    /// it and sits further into the haze. Doing this with the paint — mixing each ridge's
    /// ink towards the sky by hand — gets the colour right and the edges wrong: a ridge
    /// in haze also loses the contrast of its own shading, and only a wash over the top
    /// does both at once.
    func veil(_ ink: Ink, alpha: CGFloat, over scale: Double) {
        setFillColor(ink.cgColor(alpha: alpha))
        fill(CGRect(x: 0, y: 0, width: scale, height: scale))
    }
}
