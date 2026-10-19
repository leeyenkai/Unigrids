import CoreGraphics

/// Draws the mark at one pixel size.
///
/// A national park fills the tile — sky, sun, curved ridges receding into haze — and three
/// Unigrid brochures lie fanned across the foreground as sheets of frosted glass, the park
/// showing blurred through them. The top sheet carries the black band, which is the one
/// opaque thing in the mark and the one that says Unigrid.
///
/// Drawn at 2–4x and resampled, so curves and the fan's rotated edges stay smooth at 32 px.
struct IconRenderer {
    let pixels: Int
    let palette: Palette
    let detail: Detail
    var scene: Scene = .zion
    var variant: Variant = .light

    private var supersample: Int {
        pixels <= 256 ? 4 : 2
    }

    private var canvas: Int {
        pixels * supersample
    }

    private var scale: Double {
        Double(canvas)
    }

    private var land: Land {
        scene.land(variant)
    }

    // MARK: - The fan

    //
    // Three sheets, splayed from a pivot below the tile so they open like a hand of
    // cards. The brochure's own proportion — the federal unigrid leaf is 99 x 210 mm —
    // sets the card's shape; it lies on its side because a brochure opened flat is wider
    // than it is tall.

    private struct Card {
        let centre: CGPoint
        let rotation: Double
        /// The park this brochure is for. The front one names the park behind it; the
        /// ones under it name others, mostly hidden, which is what says the app is about
        /// the whole system rather than one park.
        let name: String?
        let designation: String
        /// The park this brochure is for — and so the park printed on its cover.
        let park: Scene
    }

    private var cards: [Card] {
        // Laid down rather than fanned open: a brochure opens flat and lands on its
        // side, and a pile of them steps back and to the left.
        //
        // The park this icon is for is the sheet on **top**, with its own land behind
        // the stack; the other two sit under it. That is the whole point of a variant:
        // a reader who picks Olympic gets Olympic on the cover and Olympic out of the
        // window, not Zion with a different brochure tucked into the pile.
        let behind = scene.others
        let all = [
            Card(
                centre: CGPoint(x: 0.378, y: 0.636),
                rotation: -0.070,
                name: behind[1].parkName,
                designation: behind[1].designation,
                park: behind[1]
            ),
            Card(
                centre: CGPoint(x: 0.468, y: 0.676),
                rotation: -0.028,
                name: behind[0].parkName,
                designation: behind[0].designation,
                park: behind[0]
            ),
            Card(
                centre: CGPoint(x: 0.570, y: 0.712),
                rotation: 0.022,
                name: scene.parkName,
                designation: scene.designation,
                park: scene
            ),
        ]
        return detail.drawsEveryBlock ? all : [all[0], all[2]]
    }

    private let cardSize = CGSize(width: 0.520, height: 0.300)
    /// Barely rounded. Paper is cut, not moulded.
    private let cardRadius = 0.030

    func image() -> CGImage? {
        guard let background = renderLandscape(),
              let context = makeContext(size: canvas)
        else { return nil }

        draw(background, in: context)

        // The glass samples a blurred copy of exactly what is behind it.
        let blurred = Glass.blurred(background, radius: scale * 0.028) ?? background

        // Each sheet prints its own park. Rendered once per park and reused, so a
        // stack of three costs three terrains rather than nine.
        var printed: [Scene: CGImage] = [scene: background]
        for card in cards where printed[card.park] == nil {
            printed[card.park] = Terrain(scene: card.park, land: card.park.land(variant))
                .render(size: canvas)
        }

        for card in cards {
            draw(
                card,
                sampling: blurred,
                photograph: printed[card.park] ?? background,
                in: context
            )
        }

        guard let full = context.makeImage() else { return nil }
        return supersample == 1 ? full : resample(full)
    }

    // MARK: - Canvas

    private func makeContext(size: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: size, height: size,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: 1, y: -1)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        return context
    }

    private func draw(_ image: CGImage, in context: CGContext) {
        context.saveGState()
        context.translateBy(x: 0, y: scale)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: scale, height: scale))
        context.restoreGState()
    }

    private func resample(_ image: CGImage) -> CGImage? {
        guard let context = makeContext(size: pixels) else { return nil }
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image, in: CGRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
        )
        return context.makeImage()
    }

    // MARK: - The park

    private func renderLandscape() -> CGImage? {
        Terrain(scene: scene, land: land).render(size: canvas)
    }

    // MARK: - The glass

    private func draw(
        _ card: Card,
        sampling blurred: CGImage,
        photograph: CGImage,
        in context: CGContext
    ) {
        let sheet = CardGeometry(
            centre: CGPoint(x: card.centre.x * scale, y: card.centre.y * scale),
            size: CGSize(width: cardSize.width * scale, height: cardSize.height * scale),
            radius: cardRadius * scale,
            rotation: card.rotation
        )
        let path = sheet.outline

        // The sheet's own shadow on what is behind it, cast from a path inset by a
        // couple of pixels.
        //
        // Cast from the sheet's own outline, the fill that throws the shadow has an
        // antialiased edge of its own, and the sheet drawn over it has another — so
        // the outermost row ends up part shadow-fill colour, which shows as a warm
        // hairline along the top of every sheet. Inset, that edge hides underneath.
        let inset = CardGeometry(
            centre: sheet.centre,
            size: CGSize(
                width: sheet.size.width - 2.5 * Double(supersample),
                height: sheet.size.height - 2.5 * Double(supersample)
            ),
            radius: sheet.radius,
            rotation: sheet.rotation
        )
        context.withShadow(offsetY: 0.018, blur: 0.034, alpha: 0.34, scale: scale) {
            context.fillFlat(inset.outline, land.ridges.last?.darkened(0.45) ?? palette.band)
        }

        context.saveGState()
        context.addPath(path)
        context.clip()

        // What shows through: the park, blurred. The frost tints it rather than hiding
        // it — a sheet you cannot see the park through is a card, not glass.
        draw(blurred, in: context)
        context.setFillColor(palette.paperFront.cgColor(alpha: palette.frostAlpha))
        context.fill(context.boundingBoxOfClipPath)

        // The cover, in the order a brochure is laid out: photograph, map panel, then
        // the type under both.
        if detail.drawsEveryBlock {
            context.saveGState()
            context.addPath(sheet.photograph)
            context.clip()
            // Enlarged and shifted, so the picture on the cover is a different view of
            // the park from the one visible through the sheet. Printed at the same
            // scale as what is behind it, it vanished into the glass.
            let frame = sheet.photograph.boundingBoxOfPath
            context.translateBy(x: 0, y: scale)
            context.scaleBy(x: 1, y: -1)
            context.draw(
                photograph,
                in: CGRect(
                    x: frame.midX - scale * 0.80,
                    y: scale - frame.maxY - scale * 0.34,
                    width: scale * 1.6,
                    height: scale * 1.6
                )
            )
            context.restoreGState()

            // A narrow sweep. Lit as hard as the paper, the map panel becomes the
            // brightest thing in the dark variant and the eye goes there first.
            context.fill(sheet.accent, with: palette.accent, sweep: 0.10)

            for rule in sheet.typeRules {
                context.fillFlat(rule, palette.textBlock.withAlpha(0.55))
            }
        }

        context.restoreGState()

        // Outside the clip: the band is already trimmed to the sheet by intersection.
        context.fill(sheet.band, with: palette.band, sweep: 0.13)

        if let name = card.name, detail.setsType {
            context.saveGState()
            context.concatenate(sheet.placement)
            Lettering.draw(
                name,
                in: sheet.nameBox,
                tracking: 0,
                ink: palette.paperFront,
                context: context
            )
            Lettering.draw(
                card.designation,
                in: sheet.designationBox,
                tracking: cardSize.width * scale * 0.004,
                ink: palette.paperFront.darkened(0.28),
                context: context
            )
            context.restoreGState()
        }
    }
}
