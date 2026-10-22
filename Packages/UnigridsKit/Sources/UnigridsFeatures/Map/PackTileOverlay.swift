import CoreGraphics
import ImageIO
import MapKit
import UniformTypeIdentifiers
import UnigridsCore
import UnigridsReference

/// A park's offline tiles as a MapKit overlay that replaces Apple's map entirely, so
/// nothing is fetched (docs/adr/0010). Past the pack's deepest zoom the deepest tile is
/// enlarged, two levels at most, so the map can come close without going blank.
final class PackTileOverlay: MKTileOverlay {
    /// How many levels past the pack's deepest the map may zoom.
    static let overzoom = 2

    let pack: OfflinePack
    private let reader: MBTilesReader?

    init(pack: OfflinePack) {
        self.pack = pack
        reader = try? MBTilesReader(url: pack.tilesURL)
        super.init(urlTemplate: nil)
        minimumZ = pack.minZoom
        maximumZ = pack.maxZoom + Self.overzoom
        canReplaceMapContent = true
        tileSize = CGSize(width: 256, height: 256)
    }

    override var boundingMapRect: MKMapRect {
        pack.rendered.mapRect
    }

    override func loadTile(
        at path: MKTileOverlayPath,
        result: @escaping (Data?, (any Error)?) -> Void
    ) {
        guard let reader else {
            result(nil, nil)
            return
        }
        let tile = path.z <= pack.maxZoom
            ? reader.tile(zoom: path.z, column: path.x, row: path.y)
            : Self.enlarged(path, from: reader, deepest: pack.maxZoom)
        // A pack is clipped to the park and a buffer, so its box has tiles it never drew;
        // without one, MapKit fills the gap with its own map, in patches.
        result(tile ?? Self.blank, nil)
    }

    /// A tile of the pack's own paper, the colour the renderer gives ground it has no
    /// elevation for (the pipeline's `style.NO_ELEVATION`).
    static let blank: Data? = {
        guard let context = CGContext(
            data: nil,
            width: 256,
            height: 256,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(red: 240 / 255, green: 238 / 255, blue: 232 / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }()

    /// The part of the deepest tile that covers `path`, scaled up to a whole tile.
    static func enlarged(
        _ path: MKTileOverlayPath,
        from reader: MBTilesReader,
        deepest: Int
    ) -> Data? {
        let factor = 1 << (path.z - deepest)
        guard let data = reader.tile(
            zoom: deepest, column: path.x / factor, row: path.y / factor
        ),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let side = image.width / factor
        let crop = CGRect(
            x: (path.x % factor) * side, y: (path.y % factor) * side, width: side, height: side
        )
        guard side > 0, let part = image.cropping(to: crop),
              let context = CGContext(
                  data: nil,
                  width: 256,
                  height: 256,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(part, in: CGRect(x: 0, y: 0, width: 256, height: 256))
        guard let scaled = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

extension BoundingBox {
    /// The box as MapKit's flat map rectangle.
    var mapRect: MKMapRect {
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: north, longitude: west))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: south, longitude: east))
        return MKMapRect(
            x: northWest.x,
            y: northWest.y,
            width: southEast.x - northWest.x,
            height: southEast.y - northWest.y
        )
    }
}
