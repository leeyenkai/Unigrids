import SwiftUI
import UnigridsCore

/// The six national faces over one layout (ADR 0013, 0014): name across the top, the
/// picture in the centre band, the date and the place's mark beneath.
struct StampFaceView: View {
    let face: StampFace
    let diameter: CGFloat
    let ink: Color

    var body: some View {
        switch face.country {
        case .unitedStates: AmericanCancellation(face: face, d: diameter, ink: ink)
        case .japan: JapaneseStamp(face: face, d: diameter, ink: ink)
        case .norway: NorwegianPostmark(face: face, d: diameter, ink: ink)
        case .newZealand: HutBookStamp(face: face, d: diameter, ink: ink)
        case .australia: BushPostCancellation(face: face, d: diameter, ink: ink)
        case .canada: BilingualCancellation(face: face, d: diameter, ink: ink)
        }
    }
}

// MARK: - Shared parts

/// The picture band every face carries, at the same place and size on each.
private struct PictureBand: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color
    var height: CGFloat = 0.3

    var body: some View {
        Group {
            if let emblem = face.emblem {
                EmblemView(emblem: emblem, ink: ink, lineWidth: max(1, d * 0.011))
                    .opacity(face.impression.inkDensity)
            } else {
                Color.clear
            }
        }
        .frame(width: d * 0.6, height: d * height)
    }
}

/// The site's name as the face sets it: capitals, shrinking before it breaks, never
/// broken at a hyphen ("FUJI-HAKONE-" over "IZU" reads as two names).
private struct NameLine: View {
    let text: String
    let size: CGFloat
    var lines = 2
    var weight: Font.Weight = .semibold
    /// Narrower than the face: near the top the circle's chord is short.
    var width: CGFloat = .infinity

    var body: some View {
        Text(text.uppercased().replacingOccurrences(of: "-", with: "\u{2011}"))
            .font(.system(size: size, weight: weight))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.55)
            .lineLimit(lines)
            .frame(maxWidth: width)
    }
}

private struct DateLine: View {
    let face: StampFace
    let size: CGFloat

    var body: some View {
        Text(face.dateLine())
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct MarkLine: View {
    let text: String
    let size: CGFloat
    var tracking: CGFloat = 0.012
    let d: CGFloat // swiftlint:disable:this identifier_name

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium))
            .tracking(d * tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: d * 0.52)
    }
}

/// The verified-on-site tick, beside the mark.
private struct VerifiedTick: View {
    let face: StampFace
    let size: CGFloat

    var body: some View {
        if face.isVerifiedOnSite {
            Image(.verified)
                .font(.system(size: size))
                .accessibilityHidden(true)
        }
    }
}

/// A circle whose edge is a ring of shallow scallops, like a hand-cut rubber stamp.
struct ScallopedCircle: Shape {
    var lobes = 32
    var depth: CGFloat = 0.035

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        let steps = lobes * 12
        for step in 0 ... steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wave = (1 - cos(angle * Double(lobes))) / 2
            let r = radius * (1 - depth * wave) // swiftlint:disable:this identifier_name
            let point = CGPoint(x: centre.x + r * cos(angle), y: centre.y + r * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Faces

/// The US book: a ranger-station cancellation, double ring, a bar under the picture,
/// the state's postal code at the foot.
private struct AmericanCancellation: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Group {
                Circle().stroke(ink, lineWidth: d * 0.022)
                Circle().stroke(ink, lineWidth: d * 0.01).padding(d * 0.055)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.018) {
                NameLine(text: face.siteName, size: d * 0.078, width: d * 0.62)
                PictureBand(face: face, d: d, ink: ink)
                Rectangle().frame(width: d * 0.5, height: d * 0.01)
                DateLine(face: face, size: d * 0.098)
                HStack(spacing: d * 0.02) {
                    MarkLine(text: face.stateCode, size: d * 0.072, tracking: 0.02, d: d)
                    VerifiedTick(face: face, size: d * 0.07)
                }
            }
            .padding(.horizontal, d * 0.16)
            .foregroundStyle(ink)
        }
    }
}

/// Japan's book, after the commemorative stamps (記念スタンプ) of its visitor centres and
/// stations: one heavy ring, the English name round the top, the picture, the park's
/// name in kanji set large, the date as Japan writes it, the prefecture.
private struct JapaneseStamp: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Circle().stroke(ink, lineWidth: d * 0.04).opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.012) {
                rimName
                PictureBand(face: face, d: d, ink: ink, height: 0.27)
                Text(face.localName ?? face.siteName)
                    .font(.system(size: d * 0.1, weight: .heavy))
                    .typesettingLanguage(Locale.Language(identifier: "ja"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                DateLine(face: face, size: d * 0.08)
                HStack(spacing: d * 0.02) {
                    MarkLine(text: face.stateCode, size: d * 0.058, d: d)
                    VerifiedTick(face: face, size: d * 0.06)
                }
            }
            .padding(.horizontal, d * 0.15)
            .foregroundStyle(ink)
        }
    }

    /// One line where it fits without shrinking far, else two broken at its hyphens
    /// (Rishiri-Rebun-Sarobetsu).
    private var rimName: some View {
        let name = face.siteName.uppercased()
        let size = d * 0.062
        return ViewThatFits(in: .horizontal) {
            Text(name.replacingOccurrences(of: "-", with: "\u{2011}"))
                .font(.system(size: size, weight: .semibold))
                .tracking(d * 0.006)
                .lineLimit(1)
                .fixedSize()
            Text(name.replacingOccurrences(of: "-", with: "-\u{200B}"))
                .font(.system(size: size * 0.85, weight: .semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
    }
}

/// Norway's book, after a Norwegian postmark: two rings, the name, the picture, the
/// date between bars that run out to the inner ring, the county and NORGE.
private struct NorwegianPostmark: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Group {
                Circle().stroke(ink, lineWidth: d * 0.018)
                Circle().stroke(ink, lineWidth: d * 0.01).padding(d * 0.07)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.016) {
                NameLine(text: face.siteName, size: d * 0.074, width: d * 0.62)
                PictureBand(face: face, d: d, ink: ink)
                HStack(spacing: d * 0.025) {
                    Rectangle().frame(height: d * 0.016)
                    DateLine(face: face, size: d * 0.09).fixedSize()
                    Rectangle().frame(height: d * 0.016)
                }
                .frame(width: d * 0.74)
                HStack(spacing: d * 0.02) {
                    MarkLine(text: "\(face.stateCode) · NORGE", size: d * 0.058, d: d)
                    VerifiedTick(face: face, size: d * 0.058)
                }
            }
            .padding(.horizontal, d * 0.13)
            .foregroundStyle(ink)
        }
    }
}

/// New Zealand's book, after the stamps in a back-country hut book: a ring of short
/// strokes like a hand-inked border inside a plain one, the name, the picture, the
/// date and the region.
private struct HutBookStamp: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Group {
                Circle().stroke(ink, lineWidth: d * 0.016)
                Circle()
                    .stroke(
                        ink,
                        style: StrokeStyle(lineWidth: d * 0.03, dash: [d * 0.012, d * 0.022])
                    )
                    .padding(d * 0.05)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.016) {
                NameLine(text: face.siteName, size: d * 0.072, width: d * 0.62)
                PictureBand(face: face, d: d, ink: ink)
                DateLine(face: face, size: d * 0.09)
                HStack(spacing: d * 0.02) {
                    // The region alone: "Manawatū-Whanganui · Aotearoa" cannot fit the
                    // circle's narrowing foot, and a long name sets without letter-spacing
                    // so it shrinks to fit rather than being cut short.
                    MarkLine(
                        text: face.stateCode,
                        size: d * 0.056,
                        tracking: face.stateCode.count > 12 ? 0 : 0.012,
                        d: d
                    )
                    VerifiedTick(face: face, size: d * 0.056)
                }
            }
            .padding(.horizontal, d * 0.16)
            .foregroundStyle(ink)
        }
    }
}

/// Australia's book, after an outback post office's cancellation: a scalloped edge
/// round a plain ring, the name, the picture, the date, the state in a box.
private struct BushPostCancellation: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Group {
                ScallopedCircle().stroke(ink, lineWidth: d * 0.018)
                Circle().stroke(ink, lineWidth: d * 0.009).padding(d * 0.065)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.016) {
                NameLine(text: face.siteName, size: d * 0.074, width: d * 0.62)
                PictureBand(face: face, d: d, ink: ink)
                DateLine(face: face, size: d * 0.09)
                HStack(spacing: d * 0.03) {
                    MarkLine(text: face.stateCode, size: d * 0.06, tracking: 0.02, d: d)
                        .padding(.horizontal, d * 0.02)
                        .overlay { Rectangle().stroke(ink, lineWidth: d * 0.008) }
                    MarkLine(text: "Australia", size: d * 0.05, d: d)
                    VerifiedTick(face: face, size: d * 0.056)
                }
            }
            .padding(.horizontal, d * 0.16)
            .foregroundStyle(ink)
        }
    }
}

/// Canada's book, bilingual as its post is: a double ring with a band of dots between,
/// the English name above the picture, the date, the French name beneath where it
/// differs, the province or territory and CANADA.
private struct BilingualCancellation: View {
    let face: StampFace
    let d: CGFloat // swiftlint:disable:this identifier_name
    let ink: Color

    var body: some View {
        ZStack {
            Group {
                Circle().stroke(ink, lineWidth: d * 0.02)
                Circle()
                    .stroke(ink, style: StrokeStyle(
                        lineWidth: d * 0.014,
                        lineCap: .round,
                        dash: [0, d * 0.03]
                    ))
                    .padding(d * 0.04)
                Circle().stroke(ink, lineWidth: d * 0.008).padding(d * 0.07)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: d * 0.014) {
                NameLine(text: face.siteName, size: d * 0.07, width: d * 0.62)
                PictureBand(face: face, d: d, ink: ink, height: 0.27)
                DateLine(face: face, size: d * 0.085)
                if let french = face.localName {
                    Text(french)
                        .font(.system(size: d * 0.056, weight: .regular).italic())
                        .typesettingLanguage(Locale.Language(identifier: "fr"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                HStack(spacing: d * 0.02) {
                    MarkLine(text: "\(face.stateCode) · Canada", size: d * 0.054, d: d)
                    VerifiedTick(face: face, size: d * 0.054)
                }
            }
            .padding(.horizontal, d * 0.17)
            .foregroundStyle(ink)
        }
    }
}
