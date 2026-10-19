import MapKit
import UnigridsCore
import UnigridsDesign

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// A place's pin: a shape in its agency's ink, filled when visited, dashed when planned,
/// with the name on a label plate once the map is close enough to read it.
final class AtlasMarkerView: MKAnnotationView {
    static let reuse = "atlas.place"

    private let shapeLayer = CAShapeLayer()
    private let tickLayer = CAShapeLayer()
    private let plateLayer = CALayer()
    private let labelLayer = CATextLayer()
    private var shape: MarkerShape = .square
    private var plateSize: CGSize = .zero

    /// Drawn larger while its place is selected.
    var isEmphasised = false {
        didSet {
            guard isEmphasised != oldValue else { return }
            let scale: CGFloat = isEmphasised ? 1.45 : 1
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            shapeLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            tickLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
            CATransaction.commit()
            zPriority = isEmphasised ? .max : .defaultUnselected
        }
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
        for layer in [plateLayer, labelLayer, shapeLayer, tickLayer] as [CALayer] {
            layer.contentsScale = Self.displayScale
            root.addSublayer(layer)
        }
        shapeLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        shapeLayer.shadowOpacity = 0.35
        shapeLayer.shadowRadius = 1.2
        shapeLayer.shadowOffset = CGSize(width: 0, height: 0.5)
        labelLayer.alignmentMode = .center
        labelLayer.truncationMode = .end
        tickLayer.fillColor = nil
        tickLayer.lineWidth = 1.8
        tickLayer.lineCap = .round
        tickLayer.lineJoin = .round
    }

    func configure(annotation: PlaceAnnotation, ink: AtlasInk, latitudeSpan: Double) {
        self.annotation = annotation
        shape = MarkerShape(tier: annotation.tier)
        let tint = ink.tint(for: annotation.place)
        let side = shape.size
        frame.size = CGSize(width: side + 8, height: side + 8)
        let rect = CGRect(x: 4, y: 4, width: side, height: side)

        // Clusters gather the smaller sites; national parks always stand alone.
        clusteringIdentifier = annotation.tier == .nationalPark ? nil : "atlas.sites"
        displayPriority = switch annotation.tier {
        case .nationalPark: .required
        case .npsUnit: .defaultHigh
        case .statePark, .federalSite: .defaultLow
        }
        collisionMode = annotation.tier == .nationalPark ? .rectangle : .circle

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.frame = root.bounds
        shapeLayer.path = shape.path(in: rect)
        let visited = annotation.status == .visited
        shapeLayer.fillColor = visited ? tint.cg : ink.paper.cg
        shapeLayer.strokeColor = visited ? ink.paper.cg : tint.cg
        let isPark = annotation.tier == .nationalPark
        shapeLayer.lineWidth = visited ? 1.5 : (isPark ? 2.8 : 2)
        shapeLayer.lineDashPattern = annotation.status == .planned ? [3, 2] : nil

        tickLayer.frame = root.bounds
        tickLayer.path = visited && annotation.tier == .nationalPark ? Self.tick(in: rect) : nil
        tickLayer.strokeColor = ink.paper.cg

        configureLabel(annotation: annotation, ink: ink, latitudeSpan: latitudeSpan)
        CATransaction.commit()

        let status = switch annotation.status {
        case .visited: ", visited"
        case .planned: ", planned"
        case .none: ""
        }
        setSpokenLabel(
            "\(annotation.place.name) \(annotation.place.designation), "
                + "\(annotation.place.statesDescription)\(status)"
        )
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
        let gap: CGFloat = 3
        // Below the shape. AppKit layers count y upward unless the view is flipped.
        #if os(iOS)
            let plateY = bounds.maxY + gap - 4
        #else
            let plateY = isFlipped ? bounds.maxY + gap - 4 : bounds.minY - gap + 4 - height
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

    private static func tick(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.midY))
        #if os(iOS)
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * 0.44,
                y: rect.minY + rect.height * 0.7
            ))
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * 0.76,
                y: rect.minY + rect.height * 0.3
            ))
        #else
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * 0.44,
                y: rect.minY + rect.height * 0.3
            ))
            path.addLine(to: CGPoint(
                x: rect.minX + rect.width * 0.76,
                y: rect.minY + rect.height * 0.7
            ))
        #endif
        return path
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

/// A cluster of smaller sites: a black square with the count reversed out of it.
final class AtlasClusterView: MKAnnotationView {
    static let reuse = "atlas.cluster"

    private let squareLayer = CALayer()
    private let countLayer = CATextLayer()

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
        countLayer.fontSize = 11
        hostLayer.addSublayer(squareLayer)
        hostLayer.addSublayer(countLayer)
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

    func configure(count: Int, ink: AtlasInk) {
        let side: CGFloat = count >= 100 ? 30 : 24
        frame.size = CGSize(width: side, height: side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        squareLayer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        squareLayer.backgroundColor = ink.band.cg
        // White on black in both schemes: the band reads on a light map and the border on
        // a dark one.
        squareLayer.borderColor = ink.bandInk.cg
        squareLayer.borderWidth = 1.5
        countLayer.frame = CGRect(x: 0, y: (side - 14) / 2 - 1, width: side, height: 15)
        countLayer.string = "\(count)"
        countLayer.foregroundColor = ink.bandInk.cg
        CATransaction.commit()
        setSpokenLabel("\(count) places")
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
