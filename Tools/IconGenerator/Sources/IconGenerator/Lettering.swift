import CoreGraphics
import CoreText
import Foundation

/// The park's name on the band.
///
/// A real Unigrid reverses its park name out of the black band in Helvetica Medium, set
/// **caps and lower case** and flush with the first grid module — the federal
/// specification is explicit about it, and all-caps is the thing that most quickly makes
/// a homage look like a pastiche. So the icon sets "Zion", not "ZION". This is the only place in
/// the whole design system where the icon carries type, and it earns it: a brochure
/// without a name on it is a blank card, which is what the fan looked like without this.
///
/// Helvetica Neue ships on every Apple platform and is the face the guides inside the app
/// already use, so the icon and the app are set in the same thing.
enum Lettering {
    /// Draws `text` in caps, left-aligned inside `box`, at a size that fits its height.
    ///
    /// `box` is in the sheet's own coordinates, so the caller's transform carries the
    /// type onto the rotated sheet with everything else.
    static func draw(
        _ text: String,
        in box: CGRect,
        face: String = "HelveticaNeue-Medium",
        tracking: CGFloat,
        ink: Ink,
        context: CGContext
    ) {
        let font = CTFontCreateWithName(face as CFString, box.height, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: ink.cgColor(),
            kCTKernAttributeName: tracking,
        ]
        let attributed = CFAttributedStringCreate(
            nil, text as CFString, attributes as CFDictionary
        )
        guard let attributed else { return }
        let line = CTLineCreateWithAttributedString(attributed)

        // Optically centred on the cap, not on the em box. Centring on the em box sits
        // the name high, because the box reserves descender space that "Zion" barely
        // uses — which is exactly how it looked wrong.
        let capHeight = CTFontGetCapHeight(font)
        let descender = CTFontGetDescent(font)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: box.minX, y: box.midY + capHeight / 2 - descender * 0.16)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
