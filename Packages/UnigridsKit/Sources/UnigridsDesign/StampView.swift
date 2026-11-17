import SwiftUI
import UnigridsCore

/// One passport impression, drawn the way a rubber cancellation lands on paper
/// (SPECIFICATION.md §9).
///
/// Everything irregular about it — the tilt, the offset, how heavily it inked — comes
/// from the seed stored with the stamp, so the same impression renders identically every
/// time, on every device, after every sync.
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
            cancellation
            if face.hasAmerica250Seal {
                america250Seal
                    .offset(x: diameter * 0.26, y: -diameter * 0.26)
            }
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(face.impression.tiltDegrees))
        .offset(x: face.impression.offsetX, y: face.impression.offsetY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Each book's own face, over the one impression system (ADR 0013): the US book's
    /// cancellation, a Japanese visitor-centre stamp, a Norwegian postmark.
    @ViewBuilder private var cancellation: some View {
        switch face.country {
        case .unitedStates: usCancellation
        case .japan: japaneseStamp
        case .norway: norwegianPostmark
        }
    }

    private var usCancellation: some View {
        ZStack {
            Group {
                Circle()
                    .stroke(ink, lineWidth: diameter * 0.022)
                Circle()
                    .stroke(ink, lineWidth: diameter * 0.012)
                    .padding(diameter * 0.055)
            }
            .opacity(face.impression.inkDensity)

            VStack(spacing: diameter * 0.03) {
                Text(face.siteName.uppercased())
                    .font(.system(size: diameter * 0.095, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(3)

                Rectangle()
                    .frame(height: diameter * 0.012)

                Text(face.dateLine())
                    .font(.system(size: diameter * 0.115, weight: .bold))
                    .monospacedDigit()

                Rectangle()
                    .frame(height: diameter * 0.012)

                Text(face.stateCode.uppercased())
                    .font(.system(size: diameter * 0.09, weight: .medium))
                    .tracking(diameter * 0.015)
            }
            .padding(.horizontal, diameter * 0.16)
            .foregroundStyle(ink)

            if face.isVerifiedOnSite {
                Image(.verified)
                    .font(.system(size: diameter * 0.13))
                    .foregroundStyle(ink)
                    .offset(y: diameter * 0.37)
                    .accessibilityHidden(true)
            }
        }
        // A tired pad prints lighter, in the rings: the lettering stays at the region
        // ink's full strength, which is what holds it to 4.5:1 on the page.
    }

    /// After the commemorative stamps (記念スタンプ) at Japan's visitor centres and
    /// stations: one heavy ring, one ink, the park's name in kanji set large, the English
    /// name over it, the date as Japan writes it, the prefecture beneath.
    private var japaneseStamp: some View {
        ZStack {
            Circle()
                .stroke(ink, lineWidth: diameter * 0.04)
                .opacity(face.impression.inkDensity)
            VStack(spacing: diameter * 0.025) {
                rimName
                Text(face.localName ?? face.siteName)
                    .font(.system(size: diameter * 0.16, weight: .heavy))
                    .typesettingLanguage(Locale.Language(identifier: "ja"))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.45)
                    .lineLimit(2)
                Text(face.dateLine())
                    .font(.system(size: diameter * 0.1, weight: .bold))
                    .monospacedDigit()
                Text(face.stateCode.uppercased())
                    .font(.system(size: diameter * 0.075, weight: .medium))
                    .tracking(diameter * 0.012)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.horizontal, diameter * 0.15)
            .foregroundStyle(ink)
            verifiedMark
        }
    }

    /// The English name over the kanji: one line where it fits without shrinking far —
    /// "FUJI-HAKONE-" over "IZU" reads as two names — and two, broken at its hyphens,
    /// where one line would shrink it past reading (Rishiri-Rebun-Sarobetsu).
    private var rimName: some View {
        let name = face.siteName.uppercased()
        let size = diameter * 0.07
        return ViewThatFits(in: .horizontal) {
            Text(name.replacingOccurrences(of: "-", with: "\u{2011}"))
                .font(.system(size: size, weight: .semibold))
                .tracking(diameter * 0.006)
                .lineLimit(1)
                .fixedSize()
            Text(name.replacingOccurrences(of: "-", with: "\u{2011}"))
                .font(.system(size: size * 0.8, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
            Text(name.replacingOccurrences(of: "-", with: "-\u{200B}"))
                .font(.system(size: size * 0.8, weight: .semibold))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
    }

    /// After a Norwegian postmark: two rings, the name round the top, the date between
    /// bars that run out to the inner ring, the county and NORGE at the foot.
    private var norwegianPostmark: some View {
        ZStack {
            Group {
                Circle()
                    .stroke(ink, lineWidth: diameter * 0.018)
                Circle()
                    .stroke(ink, lineWidth: diameter * 0.01)
                    .padding(diameter * 0.07)
            }
            .opacity(face.impression.inkDensity)
            VStack(spacing: diameter * 0.03) {
                Text(face.siteName.uppercased())
                    .font(.system(size: diameter * 0.09, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .padding(.horizontal, diameter * 0.08)
                Rectangle()
                    .frame(height: diameter * 0.02)
                Text(face.dateLine())
                    .font(.system(size: diameter * 0.11, weight: .bold))
                    .monospacedDigit()
                Rectangle()
                    .frame(height: diameter * 0.02)
                Text("\(face.stateCode) · NORGE".uppercased())
                    .font(.system(size: diameter * 0.068, weight: .medium))
                    .tracking(diameter * 0.01)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .padding(.horizontal, diameter * 0.08)
            }
            .padding(.horizontal, diameter * 0.09)
            .foregroundStyle(ink)
            verifiedMark
        }
    }

    @ViewBuilder private var verifiedMark: some View {
        if face.isVerifiedOnSite {
            Image(.verified)
                .font(.system(size: diameter * 0.13))
                .foregroundStyle(ink)
                .offset(y: diameter * 0.39)
                .accessibilityHidden(true)
        }
    }

    /// The America 250 overprint: a red seal stamped across the corner of the regular
    /// impression, for any stamp dated in 2026.
    private var america250Seal: some View {
        VStack(spacing: 0) {
            Text("AMERICA")
                .font(.system(size: diameter * 0.075, weight: .heavy))
            Text("250")
                .font(.system(size: diameter * 0.135, weight: .heavy))
        }
        .tracking(diameter * 0.006)
        .foregroundStyle(style.seal)
        .padding(.horizontal, diameter * 0.055)
        .padding(.vertical, diameter * 0.03)
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
