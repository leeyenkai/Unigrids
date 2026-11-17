import SwiftUI
import UnigridsCore
import UnigridsDesign

/// Panel 11b: credits, sources, photo credits and the non-affiliation line, across the
/// full width at the foot of the page, as they sit on the back of a brochure.
struct GuideCreditsPanel: View {
    @Environment(\.unigrid) private var style
    let credits: [String]
    let sources: [GuideSource]
    var photos: [GuideImage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(style.rule)
                .frame(height: 1)
            ForEach(Array(credits.enumerated()), id: \.offset) { _, credit in
                Text(credit)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !photos.isEmpty {
                Text(photoLine)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sources) { source in
                if let url = source.url {
                    Link(source.title, destination: url)
                        .font(UnigridStyle.caption)
                } else {
                    Text(source.title)
                        .font(UnigridStyle.caption)
                        .foregroundStyle(style.inkSecondary)
                }
            }
            NonAffiliationNotice()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var photoLine: String {
        let entries: [String] = photos.map { image in
            guard let caption = image.caption else { return image.credit }
            return "\(caption), \(image.credit)"
        }
        return "Photographs: \(entries.joined(separator: "; ")). " + Self.licenceNote(for: photos)
    }

    /// What the photographs' licences are, from the photographs themselves rather than the
    /// country: a US state park's photograph is a Commons one, not the NPS's.
    static func licenceNote(for photos: [GuideImage]) -> String {
        let publicDomain = photos.contains(where: \.isPublicDomain)
        let licensed = photos.contains { !$0.isPublicDomain }
        switch (publicDomain, licensed) {
        case (true, false):
            return "Photographs credited to the NPS are public domain."
        case (true, true):
            return "Photographs credited to the NPS are public domain; the others are used "
                + "under the licence each author chose on Wikimedia Commons, named on its page "
                + "there."
        default:
            return "Each photograph is used under the licence its author chose on Wikimedia "
                + "Commons, named on its page there."
        }
    }
}
