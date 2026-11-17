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
    /// Draws `text` left-aligned inside `box`, at a size that fits its height — or its
    /// width, for text too long to fit at that.
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
        guard var (font, line) = set(
            text,
            face: face,
            size: box.height,
            tracking: tracking,
            ink: ink
        )
        else { return }

        // A name too long for the band is set smaller until it fits, rather than run off
        // the end of the sheet. Every name that fits — all of them until Cradle
        // Mountain–Lake St Clair — is set exactly as it was.
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        if width > box.width, width > 0 {
            let size = box.height * box.width / width
            guard let fitted = set(text, face: face, size: size, tracking: tracking, ink: ink)
            else { return }
            (font, line) = fitted
        }

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

    private static func set(
        _ text: String,
        face: String,
        size: CGFloat,
        tracking: CGFloat,
        ink: Ink
    ) -> (CTFont, CTLine)? {
        let font = CTFontCreateWithName(face as CFString, size, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: ink.cgColor(),
            kCTKernAttributeName: tracking,
        ]
        guard let attributed = CFAttributedStringCreate(
            nil, text as CFString, attributes as CFDictionary
        ) else { return nil }
        return (font, CTLineCreateWithAttributedString(attributed))
    }
}
