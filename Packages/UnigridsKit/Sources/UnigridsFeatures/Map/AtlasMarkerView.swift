import MapKit
import UnigridsCore
import UnigridsDesign

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// A place's pin: a solid shape in its kind of place's colour with a white keyline, its
/// site type's pictogram reversed out of it from regional zoom, a green tick when
/// visited, a dashed ring when planned, a badge when the park has posted a closure or
/// danger alert, and the name on a plate once the map is close enough to read it.
final class AtlasMarkerView: MKAnnotationView {
    static let reuse = "atlas.place"

    private let shapeLayer = CAShapeLayer()
    private let glyphLayer = CALayer()
    private let glyphMask = CALayer()
    private let ringLayer = CAShapeLayer()
    private let tickLayer = CAShapeLayer()
    private let checkLayer = CAShapeLayer()
    private let alertLayer = CAShapeLayer()
    private let plateLayer = CALayer()
    private let labelLayer = CATextLayer()
    private var shape: MarkerShape = .square
    private var glyphSize: CGFloat = MarkerShape.square.glyphSize
    private var plateSize: CGSize = .zero

    /// Room round the pin for the ring, the tick and the alert badge.
    private static let margin: CGFloat = 7

    /// The cluster national parks join at country scale, apart from the other sites.
    static let parkCluster = "atlas.parks"

    /// Drawn larger while its place is selected.
    var isEmphasised = false {
        didSet {
            guard isEmphasised != oldValue else { return }
            let scale: CGFloat = isEmphasised ? 1.35 : 1
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            for layer in pinLayers {
                layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            }
            CATransaction.commit()
            zPriority = isEmphasised ? .max : .defaultUnselected
        }
    }

    private var pinLayers: [CALayer] {
        [shapeLayer, glyphLayer, ringLayer, tickLayer, checkLayer, alertLayer]
    }

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private var root: CALayer {
        #if os(iOS)
            layer
        #else
            if layer == nil {
                wantsLayer = true
            }
            return layer ?? CALayer()
        #endif
    }

    private func setUpLayers() {
        #if os(macOS)
            wantsLayer = true
        #endif
        let root = root
        root.masksToBounds = false
        for layer in [plateLayer, labelLayer] + pinLayers {
            layer.contentsScale = Self.displayScale
            root.addSublayer(layer)
        }
        glyphMask.contentsScale = Self.displayScale
        glyphMask.contentsGravity = .center
        glyphLayer.mask = glyphMask
        shapeLayer.strokeColor = SiteInk.pictogram.cg
        shapeLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        shapeLayer.shadowOpacity = 0.4
        shapeLayer.shadowRadius = 1.5
        shapeLayer.shadowOffset = CGSize(width: 0, height: 0.8)
        ringLayer.fillColor = nil
        ringLayer.lineWidth = 1.6
        ringLayer.lineDashPattern = [3, 2.5]
        tickLayer.fillColor = SiteInk.visitedTick.cg
        tickLayer.strokeColor = SiteInk.pictogram.cg
        tickLayer.lineWidth = 1.2
        checkLayer.fillColor = nil
        checkLayer.strokeColor = SiteInk.pictogram.cg
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        labelLayer.alignmentMode = .center
        labelLayer.truncationMode = .end
        alertLayer.lineWidth = 1.2
    }

    func configure(annotation: PlaceAnnotation, ink: AtlasInk, latitudeSpan: Double) {
        self.annotation = annotation
        shape = MarkerShape(tier: annotation.tier)
        let fill = annotation.siteType.ink.pin
        let pictogram = MapDetail.showsPictogram(for: annotation.tier, latitudeSpan: latitudeSpan)
        let compact = annotation.tier == .nationalPark && latitudeSpan > MapDetail.compactParkSpan
        // A compact park keeps a small pictogram: a bare black square reads as an empty box.
        let plain = !compact && !pictogram
        glyphSize = compact ? 9 : shape.glyphSize
        let side: CGFloat = compact ? 15 : (pictogram ? shape.pictogramSize : shape.size)
        let margin = Self.margin
        frame.size = CGSize(width: side + margin * 2, height: side + margin * 2)
        let rect = CGRect(x: margin, y: margin, width: side, height: side)

        // Clusters gather the smaller sites. National parks stand alone, except with the
        // whole country on screen, where they gather only with each other: on a phone,
        // sixty-three pins in the West are a pile, and a counted park cluster hides none.
        clusteringIdentifier = annotation.tier == .nationalPark
            ? (compact ? Self.parkCluster : nil)
            : "atlas.sites"
        displayPriority = switch annotation.tier {
        case .nationalPark: .required
        case .npsUnit: .defaultHigh
        case .statePark, .federalSite: .defaultLow
        }
        collisionMode = annotation.tier == .nationalPark ? .rectangle : .circle

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in pinLayers {
            layer.frame = root.bounds
        }
        shapeLayer.path = shape.path(in: rect)
        shapeLayer.fillColor = fill.cg
        shapeLayer.lineWidth = plain || compact ? 1.25 : 1.75

        configureGlyph(annotation: annotation, shown: !plain, rect: rect)
        configureRing(shown: annotation.status == .planned, rect: rect, ink: ink)
        configureTick(shown: annotation.status == .visited, rect: rect, small: plain || compact)
        configureAlert(
            MapDetail.showsAlertBadge(latitudeSpan: latitudeSpan) ? annotation.alert : nil,
            rect: rect,
            ink: ink
        )
        configureLabel(annotation: annotation, ink: ink, latitudeSpan: latitudeSpan)
        CATransaction.commit()

        let status = switch annotation.status {
        case .visited: ", visited"
        case .planned: ", planned"
        case .none: ""
        }
        let alert = annotation.alert.map { ", \($0.spokenName) alert posted" } ?? ""
        setSpokenLabel(
            "\(annotation.place.name) \(annotation.place.designation), "
                + "\(annotation.place.statesDescription)\(status)\(alert)"
        )
    }

    private func configureGlyph(annotation: PlaceAnnotation, shown: Bool, rect: CGRect) {
        guard shown,
              let image = PictogramCache.image(
                  UnigridsSymbol.site(annotation.siteType),
                  pointSize: glyphSize
              )
        else {
            glyphLayer.isHidden = true
            return
        }
        glyphLayer.isHidden = false
        glyphLayer.frame = rect
        glyphLayer.backgroundColor = SiteInk.pictogram.cg
        glyphMask.frame = CGRect(origin: .zero, size: rect.size)
        glyphMask.contents = image
        glyphMask.contentsScale = PictogramCache.renderScale
    }

    /// A dashed ring a little outside the pin: on a trip being planned.
    private func configureRing(shown: Bool, rect: CGRect, ink: AtlasInk) {
        ringLayer.isHidden = !shown
        guard shown else { return }
        ringLayer.path = shape.path(in: rect.insetBy(dx: -4, dy: -4))
        ringLayer.strokeColor = ink.ink.cg
    }

    /// A green disc with a white check at the pin's lower right: been there.
    private func configureTick(shown: Bool, rect: CGRect, small: Bool) {
        tickLayer.isHidden = !shown
        checkLayer.isHidden = !shown
        guard shown else { return }
        let diameter: CGFloat = small ? 8 : 11
        let originY = isUpsideDown
            ? rect.minY - diameter / 2 + 2
            : rect.maxY - diameter / 2 - 2
        let disc = CGRect(
            x: rect.maxX - diameter / 2 - 2, y: originY, width: diameter, height: diameter
        )
        tickLayer.path = CGPath(ellipseIn: disc, transform: nil)
        tickLayer.lineWidth = small ? 1 : 1.2
        checkLayer.lineWidth = small ? 1.1 : 1.5
        checkLayer.path = TickMark.path(
            in: disc.insetBy(dx: diameter * 0.28, dy: diameter * 0.3),
            flipped: isUpsideDown
        )
    }

    private func configureAlert(_ alert: MapAlertLevel?, rect: CGRect, ink: AtlasInk) {
        guard let alert else {
            alertLayer.isHidden = true
            return
        }
        alertLayer.isHidden = false
        let side: CGFloat = 9
        // Top right of the pin.
        let top = isUpsideDown ? rect.maxY - side / 2 : rect.minY - side / 2
        let badge = CGRect(x: rect.maxX - side / 2, y: top, width: side, height: side)
        alertLayer.path = CGPath(rect: badge, transform: nil)
        alertLayer.fillColor = (alert == .danger ? ink.seal : ink.ink).cg
        alertLayer.strokeColor = SiteInk.pictogram.cg
    }

    /// Whether this view's layers count y upward, as an unflipped AppKit view's do.
    private var isUpsideDown: Bool {
        #if os(iOS)
            false
        #else
            !isFlipped
        #endif
    }

    private func configureLabel(annotation: PlaceAnnotation, ink: AtlasInk, latitudeSpan: Double) {
        let shows = MapDetail.showsLabel(for: annotation.tier, latitudeSpan: latitudeSpan)
        plateLayer.isHidden = !shows
        labelLayer.isHidden = !shows
        guard shows else { return }

        // National parks print reversed out of a black plate, like the brochure band;
        // everything else on paper, smaller.
        let isPark = annotation.tier == .nationalPark
        let fontSize: CGFloat = isPark ? 11 : 9.5
        let fontName = isPark ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium"
        let text = annotation.place.name
        let textWidth = Self.width(of: text, fontName: fontName, size: fontSize)
        let width = min(textWidth + 10, 180)
        let height = fontSize + 7
        plateSize = CGSize(width: width, height: height)

        let bounds = root.bounds
        // Clear of the visited tick, which hangs a little below the pin.
        let gap: CGFloat = 5
        // Below the shape. AppKit layers count y upward unless the view is flipped.
        #if os(iOS)
            let plateY = bounds.maxY - Self.margin + gap
        #else
            let plateY = isFlipped ? bounds.maxY - Self.margin + gap
                : bounds.minY + Self.margin - gap - height
        #endif
        let plateFrame = CGRect(x: bounds.midX - width / 2, y: plateY, width: width, height: height)
        plateLayer.frame = plateFrame
        plateLayer.backgroundColor = isPark ? ink.band.cg : ink.paper.cg(alpha: 0.92)
        plateLayer.borderWidth = isPark ? (ink.scheme == .dark ? 0.75 : 0) : 0.5
        plateLayer.borderColor = isPark ? ink.bandInk.cg(alpha: 0.55) : ink.ink.cg(alpha: 0.35)

        labelLayer.frame = plateFrame.insetBy(dx: 4, dy: 0).offsetBy(dx: 0, dy: 3)
        labelLayer.frame.size.height = height - 3
        labelLayer.string = text
        labelLayer.font = CGFont(fontName as CFString)
        labelLayer.fontSize = fontSize
        labelLayer.foregroundColor = isPark ? ink.bandInk.cg : ink.ink.cg
    }

    static func width(of text: String, fontName: String, size: CGFloat) -> CGFloat {
        #if os(iOS)
            let font = UIFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        #else
            let font = NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
        #endif
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static var displayScale: CGFloat {
        #if os(iOS)
            3
        #else
            NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }
}

/// A cluster of smaller sites: a black disc with the count reversed out of it — round, so
/// it never reads as a national park's black square. National parks gathered at country
/// scale get a black square instead, with the park star beside the count.
final class AtlasClusterView: MKAnnotationView {
    static let reuse = "atlas.cluster"

    private let squareLayer = CALayer()
    private let countLayer = CATextLayer()
    private let starLayer = CALayer()
    private let starMask = CALayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        #if os(macOS)
            wantsLayer = true
        #endif
        displayPriority = .defaultHigh
        collisionMode = .rectangle
        squareLayer.contentsScale = AtlasMarkerView.displayScale
        countLayer.contentsScale = AtlasMarkerView.displayScale
        countLayer.alignmentMode = .center
        countLayer.font = CGFont("HelveticaNeue-Bold" as CFString)
        countLayer.fontSize = 10
        starMask.contentsScale = AtlasMarkerView.displayScale
        starMask.contentsGravity = .center
        starLayer.mask = starMask
        starLayer.backgroundColor = SiteInk.pictogram.cg
        hostLayer.addSublayer(squareLayer)
        hostLayer.addSublayer(countLayer)
        hostLayer.addSublayer(starLayer)
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

    func configure(count: Int, ink: AtlasInk, parks: Bool) {
        if parks {
            configureParks(count: count)
            return
        }
        let side: CGFloat = count >= 100 ? 28 : (count >= 10 ? 24 : 21)
        frame.size = CGSize(width: side, height: side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        starLayer.isHidden = true
        squareLayer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        squareLayer.cornerRadius = side / 2
        squareLayer.backgroundColor = ink.band.cg
        // White on black in both schemes: the band reads on a light map and the keyline
        // on a dark one, as a pin's does.
        squareLayer.borderColor = SiteInk.pictogram.cg
        squareLayer.borderWidth = 1.5
        squareLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        squareLayer.shadowOpacity = 0.35
        squareLayer.shadowRadius = 1.5
        squareLayer.shadowOffset = CGSize(width: 0, height: 0.8)
        countLayer.frame = CGRect(x: 0, y: (side - 13) / 2 - 1, width: side, height: 14)
        countLayer.string = "\(count)"
        countLayer.foregroundColor = ink.bandInk.cg
        CATransaction.commit()
        setSpokenLabel("\(count) places")
    }

    private func configureParks(count: Int) {
        let height: CGFloat = 20
        let width: CGFloat = 24 + CGFloat(String(count).count) * 6
        frame.size = CGSize(width: width, height: height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        squareLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        squareLayer.cornerRadius = 0
        squareLayer.backgroundColor = SiteInk.nationalPark.pin.cg
        squareLayer.borderColor = SiteInk.pictogram.cg
        squareLayer.borderWidth = 1.5
        starLayer.isHidden = false
        starLayer.frame = CGRect(x: 4, y: (height - 12) / 2, width: 12, height: 12)
        starMask.frame = CGRect(origin: .zero, size: starLayer.frame.size)
        starMask.contents = PictogramCache.image(UnigridsSymbol.site(.nationalPark), pointSize: 9)
        starMask.contentsScale = PictogramCache.renderScale
        countLayer.frame = CGRect(x: 15, y: (height - 13) / 2 - 1, width: width - 17, height: 14)
        countLayer.string = "\(count)"
        countLayer.foregroundColor = SiteInk.pictogram.cg
        CATransaction.commit()
        setSpokenLabel("\(count) national parks")
    }
}

extension MKAnnotationView {
    /// VoiceOver's label for a pin. UIKit and AppKit spell the same thing differently.
    func setSpokenLabel(_ label: String) {
        #if os(iOS)
            isAccessibilityElement = true
            accessibilityLabel = label
        #else
            setAccessibilityElement(true)
            setAccessibilityLabel(label)
        #endif
    }
}
