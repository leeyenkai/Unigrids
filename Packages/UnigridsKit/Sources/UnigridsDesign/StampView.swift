import SwiftUI
import UnigridsCore

/// One passport impression, drawn the way a rubber stamp lands on paper
/// (SPECIFICATION.md §9).
///
/// Every book shares one layout — the place's name across the top, its picture in the
/// centre, the date and the place's mark beneath — and each country's face gives it its
/// own national character: a US ranger-station cancellation, a Japanese commemorative
/// stamp, a Norwegian postmark, a New Zealand hut-book stamp, an Australian bush-post
/// cancellation, a bilingual Canadian one. None borrows an official mark.
///
/// Everything irregular — the tilt, the offset, how heavily the rings inked — comes from
/// the seed stored with the stamp, so an impression renders identically every time, on
/// every device, after every sync. The lettering keeps the region ink's full strength,
/// which is what holds it to 4.5:1 on the page; only the rings and the picture print
/// lighter on a tired pad.
public struct StampView: View {
    private let face: StampFace
    private let diameter: CGFloat

    public init(face: StampFace, diameter: CGFloat = 112) {
        self.face = face
        self.diameter = diameter
    }

    @Environment(\.unigrid) private var style

    /// Only the region ink and the seal. A stamp lands on a native passport page, not on
    /// Unigrid paper, so it must never reach for the guide's page or panel colours.
    private var ink: Color {
        style.regionInk(face.region)
    }

    public var body: some View {
        ZStack {
            StampFaceView(face: face, diameter: diameter, ink: ink)
            if face.hasAmerica250Seal {
                america250Seal
                    .offset(x: diameter * 0.27, y: -diameter * 0.27)
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(face.impression.tiltDegrees))
        .offset(x: face.impression.offsetX, y: face.impression.offsetY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The America 250 overprint: a red seal stamped across the corner of the regular
    /// impression, for any US stamp dated in 2026.
    private var america250Seal: some View {
        VStack(spacing: 0) {
            Text("AMERICA")
                .font(.system(size: diameter * 0.07, weight: .heavy))
            Text("250")
                .font(.system(size: diameter * 0.125, weight: .heavy))
        }
        .tracking(diameter * 0.006)
        .foregroundStyle(style.seal)
        .padding(.horizontal, diameter * 0.05)
        .padding(.vertical, diameter * 0.025)
        .overlay {
            RoundedRectangle(cornerRadius: diameter * 0.03)
                .stroke(style.seal, lineWidth: diameter * 0.018)
        }
        .rotationEffect(.degrees(face.impression.sealTiltDegrees))
        .opacity(0.9)
    }

    private var accessibilityLabel: String {
        var parts = [
            [face.siteName, face.localName].compactMap(\.self).joined(separator: ", ")
                + ", stamped \(face.dateLine()), \(face.stateCode)",
            "\(face.region.name) region",
        ]
        if let emblem = face.emblem {
            parts.append("picture: \(emblem.subject)")
        }
        if face.hasAmerica250Seal {
            parts.append("with the America 250 seal")
        }
        if face.isVerifiedOnSite {
            parts.append("verified on site")
        }
        return parts.joined(separator: ", ")
    }
}

/// An empty passport slot: a faint outline, so the gaps show what is left to collect.
public struct StampSlotView: View {
    @Environment(\.unigrid) private var style

    private let siteName: String
    private let diameter: CGFloat

    public init(siteName: String, diameter: CGFloat = 112) {
        self.siteName = siteName
        self.diameter = diameter
    }

    public var body: some View {
        Circle()
            .strokeBorder(
                style.rule,
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
            )
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(.add)
                    .font(.system(size: diameter * 0.2, weight: .light))
                    .foregroundStyle(style.rule)
            }
            .accessibilityLabel("\(siteName), not yet stamped")
            .accessibilityAddTraits(.isButton)
    }
}

/// A stamp's picture: an `Emblem` drawn in one ink, scaled to fit its band, its lines a
/// weight that reads at every size a stamp is shown.
public struct EmblemView: View {
    private let emblem: Emblem
    private let ink: Color
    private let lineWidth: CGFloat

    public init(emblem: Emblem, ink: Color, lineWidth: CGFloat) {
        self.emblem = emblem
        self.ink = ink
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            ForEach(Array(emblem.parts.enumerated()), id: \.offset) { _, part in
                let shape = EmblemShape(emblem: emblem, part: part)
                if part.fill {
                    shape.fill(ink)
                } else {
                    shape.stroke(
                        ink,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .aspectRatio(emblem.width / emblem.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One part of an emblem as a shape, its canvas fitted to the frame it is given.
public struct EmblemShape: Shape {
    let emblem: Emblem
    let part: Emblem.Part

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / emblem.width, rect.height / emblem.height)
        let originX = rect.midX - emblem.width * scale / 2
        let originY = rect.midY - emblem.height * scale / 2
        func point(_ value: EmblemPoint) -> CGPoint {
            CGPoint(x: originX + value.x * scale, y: originY + value.y * scale)
        }
        var path = Path()
        for segment in part.segments {
            switch segment {
            case let .move(to): path.move(to: point(to))
            case let .line(to): path.addLine(to: point(to))
            case let .quad(control, to):
                path.addQuadCurve(to: point(to), control: point(control))
            case let .cubic(control1, control2, to):
                path.addCurve(to: point(to), control1: point(control1), control2: point(control2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
