import SwiftUI
import UnigridsCore
import UnigridsDesign

// Panels a guide abroad carries that a US guide does not (ADR 0013): how the park works
// for a visitor, and its huts and cabins.

/// "How this park works": a Japanese park's zones and the towns and private land inside
/// it, Norway's right to roam and a park's own rules, Svalbard's notification and polar
/// bear rules.
struct HowItWorksPanel: View {
    @Environment(\.unigrid) private var style
    let paragraphs: [String]

    var body: some View {
        UnigridPanel(title: GuidePanel.howItWorks.title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(UnigridStyle.prose)
                        .foregroundStyle(style.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A park's mountain huts and cabins, as OpenStreetMap maps them, with who runs each
/// where the map says.
struct HutsPanel: View {
    @Environment(\.unigrid) private var style
    let huts: [PointOfInterest]

    /// Enough to plan by; the park map and the explorer show every one.
    private let shown = 12

    var body: some View {
        UnigridPanel(title: GuidePanel.huts.title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(huts.prefix(shown)) { hut in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hut.name)
                            .typeset(for: hut.name)
                            .font(UnigridStyle.itemTitle)
                            .foregroundStyle(style.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let summary = hut.summary {
                            Text(summary)
                                .font(UnigridStyle.dataLabel)
                                .foregroundStyle(style.inkSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if hut.id != huts.prefix(shown).last?.id {
                        Hairline()
                    }
                }
                if huts.count > shown {
                    // Every hut is drawn in the 3D explorer; only two parks have an offline
                    // Park map.
                    Text("\(huts.count - shown) more in Explore in 3D.")
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
                Text("Huts from OpenStreetMap contributors, ODbL. Opening and booking change "
                    + "by season: check with whoever runs a hut before you rely on it.")
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension View {
    /// Typesets text in its own language, so kanji draw in Japanese forms (Hiragino)
    /// rather than a Chinese fallback, and VoiceOver reads it in that language.
    func typeset(in language: String) -> some View {
        typesettingLanguage(Locale.Language(identifier: language))
            .environment(\.locale, Locale(identifier: language))
    }
}
