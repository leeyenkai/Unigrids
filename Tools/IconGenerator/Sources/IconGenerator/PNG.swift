import CoreGraphics
import Foundation
import ImageIO

enum GeneratorError: Error, CustomStringConvertible {
    case renderFailed(Int)
    case writeFailed(URL)

    var description: String {
        switch self {
        case let .renderFailed(pixels): "could not render at \(pixels) px"
        case let .writeFailed(url): "could not write \(url.lastPathComponent)"
        }
    }
}

enum PNG {
    /// Writes an opaque sRGB PNG. App icons must not carry an alpha channel, so the
    /// bitmap is created without one and ImageIO writes three channels.
    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else { throw GeneratorError.writeFailed(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw GeneratorError.writeFailed(url)
        }
    }
}
