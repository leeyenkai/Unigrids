import MapKit
import UnigridsCore

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// How a transport layer is drawn: a line, an optional casing under it, and an optional
/// dashed centre over it — the railway's ties.
struct TransportStyle: Equatable {
    var line: ColorValue
    var width: CGFloat
    var casing: ColorValue?
    var casingWidth: CGFloat = 0
    var centre: ColorValue?
    var centreWidth: CGFloat = 0
    var centreDash: [CGFloat] = []
}

extension AtlasInk {
    /// Road and rail in the conventions a road atlas uses, kept quieter than the parks:
    /// Interstates blue on a paper casing, US routes a thin grey, Amtrak a dark line with
    /// white ties. The dark scheme lifts each line and drops the casing to the map's black.
    func transportStyle(_ layer: TransportLayer) -> TransportStyle {
        let dark = scheme == .dark
        switch layer {
        case .interstates:
            return TransportStyle(
                line: hex(dark ? "6F9CE8" : "2B55A6"),
                width: 2.4,
                casing: dark ? hex("0D0D0D") : hex("FFFFFF"),
                casingWidth: 4.4
            )
        case .usHighways:
            // Neutral, so a US route never reads as a scenic byway, which is drawn in
            // the byway's sienna.
            return TransportStyle(
                line: hex(dark ? "C9C9C9" : "5E5E5E"),
                width: 1.4,
                casing: dark ? hex("0D0D0D") : hex("FFFFFF"),
                casingWidth: 2.6
            )
        case .amtrak:
            return TransportStyle(
                line: dark ? hex("E6E6E6") : hex("1B1B1B"),
                width: 3,
                centre: dark ? hex("1B1B1B") : hex("FFFFFF"),
                centreWidth: 1.4,
                centreDash: [5, 5]
            )
        }
    }

    private func hex(_ value: String) -> ColorValue {
        ColorValue(hex: value) ?? ink
    }
}

/// Draws a whole transport layer as one path, cased and tied as its style says.
final class TransportRenderer: MKMultiPolylineRenderer {
    private var style = TransportStyle(line: ColorValue(red: 0, green: 0, blue: 0), width: 1)

    func apply(_ style: TransportStyle) {
        self.style = style
        strokeColor = style.line.platform
        lineWidth = style.width
        lineCap = .round
        lineJoin = .round
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if path == nil {
            createPath()
        }
        guard let path else { return }
        // MapKit's line widths are in screen points; the context is in map points.
        let scale = 1 / zoomScale
        if let casing = style.casing, style.casingWidth > 0 {
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(casing.cg)
            context.setLineWidth(style.casingWidth * scale)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        }
        super.draw(mapRect, zoomScale: zoomScale, in: context)
        if let centre = style.centre, style.centreWidth > 0 {
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(centre.cg)
            context.setLineWidth(style.centreWidth * scale)
            context.setLineDash(phase: 0, lengths: style.centreDash.map { $0 * scale })
            context.strokePath()
            context.restoreGState()
        }
    }
}

/// An Amtrak station: a small ring, the rail convention, with its name close up.
final class StationMarkerView: MKAnnotationView {
    static let reuse = "atlas.station"

    private let ringLayer = CAShapeLayer()
    private let labelLayer = CATextLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        #if os(macOS)
            wantsLayer = true
        #endif
        canShowCallout = true
        displayPriority = .defaultLow
        collisionMode = .circle
        let host = hostLayer
        host.masksToBounds = false
        for layer in [ringLayer, labelLayer] as [CALayer] {
            layer.contentsScale = AtlasMarkerView.displayScale
            host.addSublayer(layer)
        }
        ringLayer.lineWidth = 2
        labelLayer.fontSize = 9
        labelLayer.font = CGFont("HelveticaNeue-Medium" as CFString)
        labelLayer.alignmentMode = .left
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private var hostLayer: CALayer {
        #if os(iOS)
            layer
        #else
            layer ?? CALayer()
        #endif
    }

    func configure(station: StationAnnotation, ink: AtlasInk, latitudeSpan: Double) {
        let side: CGFloat = 9
        frame.size = CGSize(width: side + 4, height: side + 4)
        let style = ink.transportStyle(.amtrak)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.frame = hostLayer.bounds
        ringLayer.path = CGPath(
            ellipseIn: CGRect(x: 2, y: 2, width: side, height: side), transform: nil
        )
        ringLayer.fillColor = (style.centre ?? ink.paper).cg
        ringLayer.strokeColor = style.line.cg
        // Station names only once the map is close: there are five hundred of them.
        let named = latitudeSpan <= MapDetail.stationSpan / 2
        labelLayer.isHidden = !named
        if named {
            let text = station.station.name
            let width = AtlasMarkerView.width(of: text, fontName: "HelveticaNeue-Medium", size: 9)
            labelLayer.frame = CGRect(x: side + 7, y: 1, width: width + 4, height: 12)
            labelLayer.string = text
            labelLayer.foregroundColor = ink.ink.cg
        }
        CATransaction.commit()
        setSpokenLabel("Amtrak station, \(station.station.name)")
    }
}
