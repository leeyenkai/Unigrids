import MapKit
import SwiftUI
import UnigridsCore

// MARK: - Colours

/// The colours the atlas draws in, resolved once from the Unigrid style so the map and
/// the guides agree on what a national park looks like.
struct AtlasInk: Equatable {
    let scheme: PaletteScheme
    let paper: ColorValue
    let ink: ColorValue
    let band: ColorValue
    let bandInk: ColorValue
    let seal: ColorValue

    init(scheme: PaletteScheme, palette: Palette) {
        let colors = palette.colors(scheme)
        self.scheme = scheme
        // Pins sit on map tiles no palette controls, so their paper is plain white or
        // black rather than brochure stock (docs/design-system.md, "Map pins").
        paper = scheme == .dark ? ColorValue(red: 0.11, green: 0.11, blue: 0.11)
            : ColorValue(red: 1, green: 1, blue: 1)
        ink = colors.ink
        band = colors.band
        bandInk = colors.bandInk
        seal = colors.seal
    }

    /// A place's outline and route colour: its kind of place's ink in this scheme.
    func tint(for place: Place) -> ColorValue {
        SiteInk.forPlace(place).value(scheme)
    }
}

extension ColorValue {
    var platform: PlatformColor {
        PlatformColor(red: red, green: green, blue: blue, alpha: 1)
    }

    var cg: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    func cg(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Model objects MapKit needs

final class PlaceAnnotation: NSObject, MKAnnotation {
    let placeID: UnigridsID
    let tier: PlaceTier
    let siteType: SiteType
    let place: Place
    var status: VisitStatusBadgeStatus
    var alert: MapAlertLevel?
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ item: AtlasPlace) {
        place = item.place
        placeID = item.place.id
        tier = item.place.tier
        siteType = item.place.siteType
        status = item.status
        alert = item.alert
        coordinate = item.place.centre.clCoordinate
        title = item.place.name
        subtitle = item.place.designation
    }
}

/// An Amtrak station on the rail layer.
final class StationAnnotation: NSObject, MKAnnotation {
    let station: RailStation
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ station: RailStation) {
        self.station = station
        coordinate = station.location.clCoordinate
        title = station.name
        subtitle = ["Amtrak", station.code, station.state?.name]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

/// A byway's line, as one overlay.
final class RouteOverlay: MKMultiPolyline {
    var placeID: UnigridsID = ""
}

/// A transport layer — every Interstate, say — as one overlay with one renderer, which is
/// what keeps forty thousand miles of road cheap to draw.
final class TransportOverlay: MKMultiPolyline {
    var layer: TransportLayer = .interstates
}

/// SF Symbol pictograms as Core Graphics images, for pins drawn in layers.
///
/// Rendered once per symbol and size, in black, and used as a mask, so one image serves
/// every ink and both schemes.
@MainActor
enum PictogramCache {
    static let renderScale: CGFloat = 3
    private static var images: [String: CGImage] = [:]

    static func image(_ name: String, pointSize: CGFloat) -> CGImage? {
        let key = "\(name)@\(pointSize)"
        if let cached = images[key] {
            return cached
        }
        let image = render(name, pointSize: pointSize)
        images[key] = image
        return image
    }

    private static func render(_ name: String, pointSize: CGFloat) -> CGImage? {
        #if os(iOS)
            let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            guard let symbol = UIImage(systemName: name, withConfiguration: configuration)
            else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = renderScale
            return UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in
                symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
            }.cgImage
        #else
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            else { return nil }
            let size = symbol.size
            guard let context = CGContext(
                data: nil,
                width: Int((size.width * renderScale).rounded(.up)),
                height: Int((size.height * renderScale).rounded(.up)),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.scaleBy(x: renderScale, y: renderScale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            symbol.draw(in: CGRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage()
        #endif
    }
}

/// How serious a park's live alerts are, as the map badges it: only the kinds worth
/// changing a plan for.
enum MapAlertLevel: Equatable {
    case danger
    case closure

    var spokenName: String {
        switch self {
        case .danger: "danger"
        case .closure: "closure"
        }
    }
}

final class PlaceOverlay: MKMultiPolygon {
    var placeID: UnigridsID = ""
    var tier: PlaceTier = .nationalPark
    /// Drawn from the country-scale outlines rather than the full ones.
    var isOverview = false
}

extension BoundingBox {
    init(region: MKCoordinateRegion) {
        self.init(
            south: region.center.latitude - region.span.latitudeDelta / 2,
            west: region.center.longitude - region.span.longitudeDelta / 2,
            north: region.center.latitude + region.span.latitudeDelta / 2,
            east: region.center.longitude + region.span.longitudeDelta / 2
        )
    }
}

extension MKMapRect {
    init(box: BoundingBox) {
        let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: box.north, longitude: box.west))
        let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: box.south, longitude: box.east))
        self.init(
            x: min(northWest.x, southEast.x),
            y: min(northWest.y, southEast.y),
            width: abs(southEast.x - northWest.x),
            height: abs(southEast.y - northWest.y)
        )
    }
}
