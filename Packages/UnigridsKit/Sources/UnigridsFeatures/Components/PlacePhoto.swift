import ImageIO
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

/// A decoded photograph, handed from the decoding task to the view.
///
/// `CGImage` is immutable once made, which is what makes passing one across the actor
/// boundary safe; the type system just cannot see that.
struct DecodedPhoto: @unchecked Sendable {
    let image: CGImage
}

/// Fetches, downsamples and remembers photographs.
///
/// Bundled guide photos are read from the app; NPS and Commons photos of the smaller
/// places are fetched once and kept by the shared URL cache, so a demo on a train still
/// shows every place the reader has already looked at. Decoding happens off the main
/// actor and to the size the view needs, because a full-size JPEG decoded on the main
/// thread is a dropped frame per photo.
actor PhotoPipeline {
    static let shared = PhotoPipeline()

    private var memory: [String: DecodedPhoto] = [:]
    private var order: [String] = []
    private let capacity = 48
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 160 * 1024 * 1024
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
    }

    func photo(at url: URL, maxPixels: Int) async -> DecodedPhoto? {
        let key = "\(url.absoluteString)#\(maxPixels)"
        if let cached = memory[key] {
            return cached
        }
        let data: Data? = if url.isFileURL {
            try? Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            try? await session.data(from: url).0
        }
        guard let data, let decoded = Self.decode(data, maxPixels: maxPixels) else { return nil }
        remember(decoded, for: key)
        return decoded
    }

    private func remember(_ photo: DecodedPhoto, for key: String) {
        memory[key] = photo
        order.append(key)
        if order.count > capacity {
            memory[order.removeFirst()] = nil
        }
    }

    private static func decode(_ data: Data, maxPixels: Int) -> DecodedPhoto? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return DecodedPhoto(image: image)
    }
}

/// A place's photograph, filling its frame, with a quiet placeholder until it arrives and
/// an honest one if it never does.
struct PlacePhoto: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(\.displayScale) private var displayScale

    let image: GuideImage
    /// Width over height. The photo fills and crops to it.
    var aspectRatio: CGFloat = 3 / 2
    /// The largest edge the view will ever be drawn at, in points.
    var maxPoints: CGFloat = 900

    @State private var decoded: DecodedPhoto?
    @State private var failed = false

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let decoded {
                    Image(decorative: decoded.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    placeholder
                }
            }
            .clipped()
            .task(id: image) { await load() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(image.altText ?? image.caption ?? "Photograph")
            .accessibilityAddTraits(.isImage)
    }

    private var placeholder: some View {
        ZStack {
            style.rule.opacity(0.5)
            if failed {
                Image(.photo)
                    .font(.title3)
                    .foregroundStyle(style.inkSecondary)
            }
        }
    }

    private func load() async {
        guard let url = store.imageURL(for: image) else {
            failed = true
            return
        }
        let pixels = Int(maxPoints * max(displayScale, 1))
        let photo = await PhotoPipeline.shared.photo(at: url, maxPixels: pixels)
        withAnimation(.easeOut(duration: 0.2)) {
            decoded = photo
            failed = photo == nil
        }
    }
}

/// A photograph's credit line, which travels with every reused image
/// (SPECIFICATION.md §6, §15).
struct PhotoCredit: View {
    @Environment(\.unigrid) private var style
    @Environment(\.dynamicTypeSize) private var typeSize
    let image: GuideImage

    var body: some View {
        // Side by side while they fit; at the largest sizes the caption and the credit
        // stack and wrap, since a credit cut short is a credit not given.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            if let caption = image.caption {
                Text(caption)
                    .foregroundStyle(style.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                if !typeSize.isAccessibilitySize {
                    Text("·")
                }
            }
            Group {
                if let url = image.sourceURL {
                    Link(image.creditLine, destination: url)
                } else {
                    Text(image.creditLine)
                }
            }
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
        .font(UnigridStyle.caption)
        .foregroundStyle(style.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
