import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

// The homage the app is built on, told once Japan's or Norway's parks ship: the national
// park idea began at Yellowstone and travelled (SPECIFICATION.md §1, ADR 0013).

/// The idea in dates. Each one is checked: Yellowstone and Roosevelt's record from the
/// NPS, Japan's dates from the Ministry of the Environment's own history of its parks,
/// Rondane from the Norwegian Environment Agency.
enum TheIdeaThatTravelled {
    static let title = "The idea that travelled"

    static let text = "Yellowstone, set aside in 1872, was the world's first national park. "
        + "Theodore Roosevelt, president from 1901 to 1909, made conservation national "
        + "policy: five national parks, eighteen national monuments and 150 national forests. "
        + "The National Park Service followed in 1916, and in 1977 it gave its brochures the "
        + "black band and grid these guides are drawn in. The idea travelled. Japan passed "
        + "its National Parks Act in 1931 and named its first three parks — Setonaikai, Unzen "
        + "and Kirishima — on 16 March 1934. Norway made Rondane its first in 1962."

    static let milestones: [(year: String, text: String)] = [
        ("1872", "Yellowstone"),
        ("1916", "The National Park Service"),
        ("1934", "Setonaikai, Unzen, Kirishima"),
        ("1962", "Rondane"),
    ]
}

/// The milestones as a ruled timeline, the chronology panel's look.
struct IdeaTimelineArt: View {
    @Environment(\.unigrid) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(TheIdeaThatTravelled.milestones, id: \.year) { milestone in
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(milestone.year)
                        .font(UnigridStyle.figureSmall)
                        .foregroundStyle(style.ink)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .leading)
                    Text(milestone.text)
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.ink)
                }
                .accessibilityElement(children: .combine)
                Hairline()
            }
        }
    }
}

/// Shown once to a reader who saw the welcome before Japan and Norway arrived: what is
/// new, and why it still looks like an American park brochure.
struct WorldWelcomeView: View {
    @Environment(\.unigrid) private var style
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            BandHeader("Unigrids", kicker: "A field guide to the world's public lands")
            OnboardingPanel(
                number: 1,
                title: TheIdeaThatTravelled.title,
                text: TheIdeaThatTravelled.text
                    + " Unigrids now has Japan's and Norway's national parks, each with a full "
                    + "guide and a passport book of its own."
            ) {
                IdeaTimelineArt()
            }
            HStack {
                Spacer()
                Button("Start exploring", action: onFinish)
                    .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(UnigridStyle.pageMargin)
        }
        .background(style.page)
    }
}
