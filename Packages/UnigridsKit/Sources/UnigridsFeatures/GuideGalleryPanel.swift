import MapKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// The gallery: the park's further NPS photographs, each with its credit, opening full
/// screen on a tap.
struct GalleryPanel: View {
    @Environment(\.unigrid) private var style
    let images: [GuideImage]

    @State private var enlarged: GuideImage?

    var body: some View {
        UnigridPanel(title: GuidePanel.gallery.title) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200), spacing: 10, alignment: .top)],
                spacing: 14
            ) {
                ForEach(images, id: \.self) { image in
                    Button {
                        enlarged = image
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            PlacePhoto(image: image, aspectRatio: 4 / 3, maxPoints: 420)
                            PhotoCredit(image: image)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .unigridsSheet(item: $enlarged) { image in
            PhotoViewer(image: image)
        }
    }
}

/// One photograph, as large as the screen allows, with its credit.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.unigrid) private var style
    let image: GuideImage

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                PlacePhoto(image: image, aspectRatio: 3 / 2, maxPoints: 1600)
                PhotoCredit(image: image)
                    .padding(.horizontal, 16)
                if let alt = image.altText {
                    Text(alt)
                        .font(UnigridStyle.proseSmall)
                        .foregroundStyle(style.inkSecondary)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 0)
            }
            .background(style.page)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheetSize(width: 900, height: 700)
    }
}
