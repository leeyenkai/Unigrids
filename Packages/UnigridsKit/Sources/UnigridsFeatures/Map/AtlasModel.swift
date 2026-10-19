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
    }

    func tint(for place: Place) -> ColorValue {
        AgencyInk.forPlace(agency: place.agency, tier: place.tier).value(scheme)
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
    let place: Place
    var status: VisitStatusBadgeStatus
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?

    init(_ item: AtlasPlace) {
        place = item.place
        placeID = item.place.id
        tier = item.place.tier
        status = item.status
        coordinate = item.place.centre.clCoordinate
        title = item.place.name
        subtitle = item.place.designation
    }
}

final class PlaceOverlay: MKMultiPolygon {
    var placeID: UnigridsID = ""
    var tier: PlaceTier = .nationalPark
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
