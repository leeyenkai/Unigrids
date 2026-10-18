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

    private var cancellation: some View {
        ZStack {
            Circle()
                .stroke(ink, lineWidth: diameter * 0.022)
            Circle()
                .stroke(ink, lineWidth: diameter * 0.012)
                .padding(diameter * 0.055)

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
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: diameter * 0.13))
                    .foregroundStyle(ink)
                    .offset(y: diameter * 0.37)
                    .accessibilityHidden(true)
            }
        }
        // A tired pad prints lighter. Ink density is the one part of the impression a
        // reader notices without being able to name.
        .opacity(face.impression.inkDensity)
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
            "\(face.siteName), stamped \(face.dateLine()), \(face.stateCode)",
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
                Image(systemName: "plus")
                    .font(.system(size: diameter * 0.2, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("\(siteName), not yet stamped")
            .accessibilityAddTraits(.isButton)
    }
}
