import PDFKit
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsReference

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

// MARK: - The viewer

/// A park's official documents, the brochure first, in a zoomable PDF view.
struct BrochureScreen: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(BrochureLibrary.self) private var library: BrochureLibrary?
    @Environment(\.dismiss) private var dismiss
    let place: Place

    @State private var selected: ParkDocument?
    @State private var file: URL?
    @State private var failed = false
    @State private var retries = 0

    private var documents: ParkDocuments? {
        store.documents(for: place.id)
    }

    var body: some View {
        SheetPage(
            selected?.title ?? "Official brochure",
            kicker: place.name,
            actions: .done { dismiss() },
            width: 900,
            height: 760
        ) {
            VStack(spacing: 0) {
                if let list = documents?.documents, list.count > 1 {
                    DocumentPicker(documents: list, selected: $selected)
                }
                content
            }
            .toolbar { toolbar }
            .task(id: LoadKey(document: selected, attempt: retries)) { await load() }
            .onAppear {
                if selected == nil {
                    selected = documents?.primary
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if documents?.documents.isEmpty ?? true {
            unavailable(
                title: "No brochure to show",
                message: "The NPS does not link a PDF from \(place.name)'s maps page. Its maps "
                    + "and brochure may be on nps.gov."
            )
        } else if failed {
            unavailable(
                title: "This brochure could not be opened",
                message: "It needs a connection the first time, and the NPS may have moved it. "
                    + "The park's maps page will have the current one.",
                retry: { retries += 1 }
            )
        } else if let file {
            PDFKitView(url: file)
                .ignoresSafeArea(edges: .bottom)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                Text("Fetching from nps.gov" + (selected?.bytes.map {
                    ", " + ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
                } ?? ""))
                    .font(UnigridStyle.rowDetail)
                    .foregroundStyle(style.inkSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func unavailable(
        title: String,
        message: String,
        retry: (() -> Void)? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, symbol: .brochure)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
            }
            if let page = documents?.page ?? place.officialURL {
                Link(destination: page) {
                    Label("Open the maps page", symbol: .website)
                }
                .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let library, let documents, !documents.documents.isEmpty {
            ToolbarItem {
                Toggle(isOn: Binding(
                    get: { library.isPinned(place.id) },
                    set: { isOn in
                        Task {
                            await library.setPinned(
                                isOn, place: place.id, documents: documents.documents
                            )
                        }
                    }
                )) {
                    Label("Save for offline", symbol: .saveOffline)
                }
                .toggleStyle(.button)
            }
        }
        if let file {
            ToolbarItem {
                ShareLink(item: file) {
                    Label("Share", symbol: .share)
                }
            }
        }
        if let url = selected?.url {
            ToolbarItem {
                Link(destination: url) {
                    Label("Website", symbol: .website)
                }
            }
        }
    }

    /// Load the selected document. A load superseded by another tab is cancelled, and a
    /// cancelled load reports nothing: it once set "could not be opened" after the next
    /// document had already cleared it, and the error stuck.
    private func load() async {
        file = nil
        failed = false
        guard let selected, let library else { return }
        do {
            let url = try await library.fetch(selected, for: place.id)
            guard !Task.isCancelled else { return }
            file = url
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}

private struct LoadKey: Hashable {
    let document: ParkDocument?
    let attempt: Int
}

/// The documents a park publishes, as square tabs across the top.
private struct DocumentPicker: View {
    @Environment(\.unigrid) private var style
    let documents: [ParkDocument]
    @Binding var selected: ParkDocument?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(documents) { document in
                    Button { selected = document } label: {
                        FilterChip(
                            title: document.title,
                            symbol: document.kind == .brochure ? "doc.richtext" : "map",
                            isOn: selected == document
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .background(style.band)
    }
}

// PDFKit's view, which gives zoom, pan and page-turning between the brochure's two sides.
#if os(iOS)
    struct PDFKitView: UIViewRepresentable {
        let url: URL

        func makeUIView(context _: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.displaysPageBreaks = true
            view.document = PDFDocument(url: url)
            return view
        }

        func updateUIView(_ view: PDFView, context _: Context) {
            if view.document?.documentURL != url {
                view.document = PDFDocument(url: url)
            }
        }
    }
#else
    struct PDFKitView: NSViewRepresentable {
        let url: URL

        func makeNSView(context _: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.displaysPageBreaks = true
            view.document = PDFDocument(url: url)
            return view
        }

        func updateNSView(_ view: PDFView, context _: Context) {
            if view.document?.documentURL != url {
                view.document = PDFDocument(url: url)
            }
        }
    }
#endif

/// The guide's and the leaflet's way into the brochure.
struct BrochurePanel: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(BrochureLibrary.self) private var library: BrochureLibrary?
    let place: Place
    let onOpen: () -> Void

    var body: some View {
        if let documents = store.documents(for: place.id) {
            UnigridPanel(title: "Official brochure") {
                VStack(alignment: .leading, spacing: 10) {
                    if let primary = documents.primary {
                        Text(primary.title)
                            .font(UnigridStyle.itemTitle)
                            .foregroundStyle(style.ink)
                        Text(detail(primary, count: documents.documents.count))
                            .font(UnigridStyle.caption)
                            .foregroundStyle(style.inkSecondary)
                        Button(action: onOpen) {
                            Label("Open the brochure", symbol: .brochure)
                        }
                        .buttonStyle(BrochureButtonStyle(.secondary))
                    } else if let page = documents.page {
                        Text("The NPS publishes this park's maps and brochure on its own site.")
                            .font(UnigridStyle.prose)
                            .foregroundStyle(style.inkSecondary)
                        Link(destination: page) {
                            Label("Maps on nps.gov", symbol: .website)
                        }
                        .buttonStyle(BrochureButtonStyle(.secondary))
                    }
                }
            }
        }
    }

    private func detail(_ document: ParkDocument, count: Int) -> String {
        var parts = ["PDF from the National Park Service"]
        if let bytes = document.bytes {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if library?.localFile(for: document) != nil {
            parts.append("on this device")
        }
        if count > 1 {
            parts.append("\(count - 1) more map\(count == 2 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }
}
