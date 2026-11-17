import Photos
import PhotosUI
import SwiftUI
import UnigridsDesign

/// Photos chosen for a check-in, from the library (SPECIFICATION.md §9). Only the
/// library's identifiers are kept: no copies, and nothing leaves the device. Taking a
/// photo off unlinks it; the photo stays in the library.
struct CheckInPhotosSection: View {
    @Environment(\.unigrid) private var style
    @Binding var identifiers: [String]
    @State private var picked: [PhotosPickerItem] = []

    /// As many as photo import links to one check-in.
    static let limit = 50

    var body: some View {
        Section {
            if !identifiers.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(identifiers, id: \.self) { id in
                            PhotoThumbnail(identifier: id)
                                .frame(width: 64, height: 64)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        identifiers.removeAll { $0 == id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(3)
                                    .accessibilityLabel("Remove this photo")
                                }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            PhotosPicker(
                selection: $picked,
                maxSelectionCount: Self.limit,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label(
                    identifiers.isEmpty ? "Add photos" : "Add more photos",
                    systemImage: "photo.on.rectangle"
                )
                .font(UnigridStyle.rowTitle)
            }
            .onChange(of: picked) {
                let new = picked.compactMap(\.itemIdentifier).filter { !identifiers.contains($0) }
                identifiers = Array((identifiers + new).prefix(Self.limit))
                picked = []
                Task { await Self.askToShowThumbnails() }
            }
        } header: {
            SectionHead("Photos", detail: identifiers.isEmpty ? nil : "\(identifiers.count)")
        } footer: {
            FormNote("Linked from your library, not copied.")
        }
    }

    /// The picker needs no permission, but drawing a thumbnail later does: asked once,
    /// the first time a photo is linked.
    private static func askToShowThumbnails() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
