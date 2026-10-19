import CoreGraphics
import CoreImage

/// Frosted glass, as the system's own material behaves.
///
/// Not a white rectangle at reduced opacity. Glass does four things at once, and leaving
/// any of them out is what makes a flat overlay look like a sticker: it **blurs** what is
/// behind it, **tints** it towards white, catches a **rim light** along the edges facing
/// the light, and **casts a shadow** onto whatever it sits above.
///
/// The blur is a real Gaussian through CoreImage rather than an approximation, because an
/// unblurred landscape read straight through the card at full detail and the card stopped
/// looking like a surface at all.
enum Glass {
    /// Blurs an image by `radius` pixels, clamped at the edges so the blur does not pull
    /// transparency in from outside the frame and darken the border.
    static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let source = CIImage(cgImage: image)
        guard let clamp = CIFilter(name: "CIAffineClamp") else { return nil }
        clamp.setValue(source, forKey: kCIInputImageKey)
        clamp.setValue(CGAffineTransform.identity, forKey: "inputTransform")

        guard let blur = CIFilter(name: "CIGaussianBlur"),
              let clamped = clamp.outputImage
        else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = blur.outputImage else { return nil }
        return context.createCGImage(output, from: source.extent)
    }
}

/// One sheet in the fan, and everything printed on it.
///
/// Every part is built in the sheet's own coordinates and then put through one shared
/// transform. Positioning the band by trigonometry against a rotated card was how it
/// ended up floating in the middle of the leftmost sheet.
struct CardGeometry {
    let centre: CGPoint
    let size: CGSize
    let radius: CGFloat
    let rotation: CGFloat

    private var transform: CGAffineTransform {
        CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: rotation)
    }

    private func place(_ path: CGPath) -> CGPath {
        var transform = transform
        return path.copy(using: &transform) ?? path
    }

    private var box: CGRect {
        CGRect(
            x: -size.width / 2, y: -size.height / 2,
            width: size.width, height: size.height
        )
    }

    /// The sheet itself: rounded hard, because a brochure that has been folded and
    /// thumbed has no sharp corners left and neither does anything else on a home screen.
    var outline: CGPath {
        place(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }

    /// How deep the band runs. On a leaf lying on its side the band is across the head,
    /// which is a larger share of the height than it is of the length.
    var bandDepth: CGFloat {
        size.height * 0.255
    }

    /// Where the park's name sits: inside the band, flush with the first grid module.
    var nameBox: CGRect {
        CGRect(
            x: box.minX + size.width * 0.055,
            y: box.minY + bandDepth * 0.26,
            width: size.width * 0.70,
            height: bandDepth * 0.46
        )
    }

    /// The transform that carries type and anything else onto the rotated sheet.
    var placement: CGAffineTransform {
        transform
    }

    /// The black band across the head, as a path in its own right rather than a
    /// rectangle clipped to the sheet.
    ///
    /// Clipping it left a pale hairline along the sheet's top edge: the clip's own
    /// antialiasing composites the band at partial coverage over the frost already
    /// painted underneath, so the topmost row of the band is a blend of the two rather
    /// than the band. Intersecting the two paths and filling the result gives one
    /// antialiased edge instead of two stacked, and the seam goes.
    var band: CGPath {
        let depth = bandDepth
        // Overhanging the sheet on every side it touches. Sharing an edge with the
        // sheet means two antialiased edges a fraction of a pixel apart, and the
        // background glints through the gap as a broken hairline along the top.
        return place(CGPath(
            roundedRect: CGRect(
                x: box.minX - radius, y: box.minY - radius,
                width: box.width + radius * 2, height: depth + radius * 2
            ),
            cornerWidth: radius, cornerHeight: radius, transform: nil
        )).intersection(outline)
    }

    /// Where the park's designation sits, under the name inside the band.
    var designationBox: CGRect {
        CGRect(
            x: box.minX + size.width * 0.058,
            y: box.minY + bandDepth * 0.70,
            width: size.width * 0.62,
            height: bandDepth * 0.17
        )
    }

    /// The photograph across the measure, directly under the band — panel 2 of the
    /// guide, and the first thing on any real cover.
    var photograph: CGPath {
        let top = box.minY + bandDepth + size.height * 0.055
        return place(CGPath(
            rect: CGRect(
                x: box.minX + size.width * 0.058,
                y: top,
                width: size.width * 0.884,
                height: size.height * 0.33
            ),
            transform: nil
        ))
    }

    /// Set type under the photograph: three columns of rules on the brochure's own grid.
    ///
    /// Individual rules rather than three solid blocks. A block is a placeholder; a run
    /// of thin lines of unequal length is what a column of type looks like from across
    /// a room, which is the distance an icon is always read from.
    var typeRules: [CGPath] {
        let top = box.minY + bandDepth + size.height * 0.425
        let bottom = box.maxY - size.height * 0.085
        let margin = size.width * 0.058
        let measure = size.width - margin * 2
        let gutter = measure * 0.045
        let column = (measure - gutter * 2) / 3

        let lines = 5
        let leading = (bottom - top) / CGFloat(lines)
        let rule = leading * 0.42
        // Unequal last lines, so each column ends like a paragraph rather than a block.
        let lastLine: [CGFloat] = [0.58, 0.82, 0.41]

        return (0 ..< 3).flatMap { index -> [CGPath] in
            let left = box.minX + margin + CGFloat(index) * (column + gutter)
            return (0 ..< lines).map { line in
                let width = line == lines - 1 ? column * lastLine[index] : column
                return place(CGPath(
                    rect: CGRect(
                        x: left,
                        y: top + CGFloat(line) * leading,
                        width: width,
                        height: rule
                    ),
                    transform: nil
                ))
            }
        }
    }

    /// The one block of colour: the map panel beside the photograph.
    var accent: CGPath {
        place(CGPath(
            roundedRect: CGRect(
                x: box.maxX - size.width * 0.058 - size.width * 0.17,
                y: box.minY + bandDepth + size.height * 0.055,
                width: size.width * 0.17,
                height: size.height * 0.33
            ),
            // Square: a rounded one reads as the chip on a bank card.
            cornerWidth: 0, cornerHeight: 0, transform: nil
        ))
    }
}
