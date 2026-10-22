import CryptoKit
import Foundation
import Observation
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

// The official brochure viewer (SPECIFICATION.md §6): each park's PDFs as the NPS
// publishes them, fetched from nps.gov the first time they are opened and kept on the
// device. Parks on an upcoming trip are saved for offline automatically; Save for offline
// covers any other. Nothing is extracted from a brochure — it is shown as published, with
// its credits (§15).

// MARK: - The library

/// The brochures kept on this device.
///
/// Files live in the app's own Application Support folder, excluded from backup: they are
/// copies of public documents the app can fetch again, not the reader's data, and they
/// belong in neither a backup nor sync — an iCloud backup full of re-downloadable PDFs is
/// what Apple's storage guidelines ask apps not to make.
@MainActor
@Observable
public final class BrochureLibrary {
    public struct Entry: Identifiable, Hashable, Codable, Sendable {
        public let url: URL
        public let placeID: String
        public let title: String
        public let file: String
        public var bytes: Int
        public let savedAt: Date

        public var id: URL {
            url
        }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var downloading: Set<URL> = []
    private(set) var pinned: Set<String>
    private let directory: URL
    private let defaults: UserDefaults
    /// Downloads under way, so a document asked for twice is fetched once.
    private var inFlight: [URL: Task<URL, any Error>] = [:]
    private static let pinnedKey = "brochures.pinned"
    private static let prefetchedKey = "brochures.lastPrefetch"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinned = Set(defaults.stringArray(forKey: Self.pinnedKey) ?? [])
        directory = URL.applicationSupportDirectory
            .appending(path: "Unigrids/Brochures", directoryHint: .isDirectory)
        Self.moveEarlierLibrary(to: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        entries = loadIndex()
    }

    /// Earlier builds kept brochures in `Application Support/Brochures` — on the Mac, while
    /// the app is not sandboxed, a folder in the user's own Library with no name of the
    /// app's on it. Moved once, and only if it holds this library's index.
    private static func moveEarlierLibrary(to destination: URL) {
        let earlier = URL.applicationSupportDirectory.appending(path: "Brochures")
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path),
              manager.fileExists(atPath: earlier.appending(path: "index.json").path)
        else { return }
        try? manager.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? manager.moveItem(at: earlier, to: destination)
    }

    public var totalBytes: Int {
        entries.reduce(0) { $0 + $1.bytes }
    }

    func localFile(for document: ParkDocument) -> URL? {
        guard let entry = entries.first(where: { $0.url == document.url }) else { return nil }
        let file = directory.appendingPathComponent(entry.file)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    func isPinned(_ placeID: UnigridsID) -> Bool {
        pinned.contains(placeID.rawValue)
    }

    /// Save a park's documents for offline, or stop keeping them on purpose.
    func setPinned(_ isPinned: Bool, place: UnigridsID, documents: [ParkDocument]) async {
        if isPinned {
            pinned.insert(place.rawValue)
        } else {
            pinned.remove(place.rawValue)
        }
        defaults.set(Array(pinned).sorted(), forKey: Self.pinnedKey)
        if isPinned {
            for document in documents {
                _ = try? await fetch(document, for: place)
            }
        }
    }

    /// The document's file on this device, fetching it from the NPS if it is not here.
    /// `inexpensiveOnly` keeps a download the reader did not ask for off cellular and Low
    /// Data networks.
    func fetch(
        _ document: ParkDocument,
        for placeID: UnigridsID,
        inexpensiveOnly: Bool = false
    ) async throws -> URL {
        if let local = localFile(for: document) {
            return local
        }
        if let running = inFlight[document.url] {
            return try await running.value
        }
        let task = Task { try await download(
            document,
            for: placeID,
            inexpensiveOnly: inexpensiveOnly
        ) }
        inFlight[document.url] = task
        downloading.insert(document.url)
        defer {
            inFlight[document.url] = nil
            downloading.remove(document.url)
        }
        return try await task.value
    }

    private func download(
        _ document: ParkDocument,
        for placeID: UnigridsID,
        inexpensiveOnly: Bool
    ) async throws -> URL {
        var request = URLRequest(url: document.url, timeoutInterval: 60)
        request.setValue(
            "Unigrids (iOS and macOS app; no tracking)",
            forHTTPHeaderField: "User-Agent"
        )
        request.allowsExpensiveNetworkAccess = !inexpensiveOnly
        request.allowsConstrainedNetworkAccess = !inexpensiveOnly
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let name = Self.fileName(for: document.url)
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        // A PDF that will not open is not worth keeping: the link has gone stale and now
        // serves an error page, which is exactly when the maps page is the better answer.
        guard PDFDocument(url: destination) != nil else {
            try? FileManager.default.removeItem(at: destination)
            throw URLError(.cannotDecodeContentData)
        }
        let size = (try? FileManager.default
            .attributesOfItem(atPath: destination.path)[.size] as? Int)
            ?? 0
        entries.removeAll { $0.url == document.url }
        entries.append(Entry(
            url: document.url,
            placeID: placeID.rawValue,
            title: document.title,
            file: name,
            bytes: size,
            savedAt: Date()
        ))
        saveIndex()
        return destination
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
        entries.removeAll { $0.url == entry.url }
        pinned.remove(entry.placeID)
        defaults.set(Array(pinned).sorted(), forKey: Self.pinnedKey)
        saveIndex()
    }

    func removeAll() {
        for entry in entries {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry.file))
        }
        entries = []
        pinned = []
        defaults.removeObject(forKey: Self.pinnedKey)
        saveIndex()
    }

    /// Save the brochures of the parks on upcoming trips, at most once a day, and only on
    /// a network the system does not count as expensive. The day is only marked done once
    /// every one is here: a run cut short — on cellular, or because the trips changed
    /// while it ran — tries again next time rather than waiting a day.
    func prefetch(placeIDs: [UnigridsID], store: any ReferenceStore) async {
        let last = defaults.object(forKey: Self.prefetchedKey) as? Date
        if let last, Date().timeIntervalSince(last) < 86400 {
            return
        }
        var complete = true
        for placeID in placeIDs {
            guard !Task.isCancelled else { return }
            guard let primary = store.documents(for: placeID)?.primary,
                  localFile(for: primary) == nil else { continue }
            do {
                _ = try await fetch(primary, for: placeID, inexpensiveOnly: true)
            } catch {
                complete = false
            }
        }
        if complete, !Task.isCancelled {
            defaults.set(Date(), forKey: Self.prefetchedKey)
        }
    }

    private static func fileName(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined() + ".pdf"
    }

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    private func loadIndex() -> [Entry] {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.filter {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.file).path)
        }
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}

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
        NavigationStack {
            VStack(spacing: 0) {
                if let list = documents?.documents, list.count > 1 {
                    DocumentPicker(documents: list, selected: $selected)
                }
                content
            }
            .background(style.page)
            .navigationTitle(selected?.title ?? place.name)
            .toolbarTitleDisplayMode(.inline)
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
            Label(title, systemImage: "doc.richtext")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(BrochureButtonStyle(.secondary, fullWidth: false))
            }
            if let page = documents?.page ?? place.officialURL {
                Link(destination: page) {
                    Label("Open the maps page", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(BrochureButtonStyle(.primary, fullWidth: false))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
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
                    Label("Save for offline", systemImage: "arrow.down.circle")
                }
                .toggleStyle(.button)
            }
        }
        if let file {
            ToolbarItem {
                ShareLink(item: file) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        if let url = selected?.url {
            ToolbarItem {
                Link(destination: url) {
                    Label("On nps.gov", systemImage: "safari")
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
                            Label("Open the brochure", systemImage: "doc.richtext")
                        }
                        .buttonStyle(BrochureButtonStyle(.secondary))
                    } else if let page = documents.page {
                        Text("The NPS publishes this park's maps and brochure on its own site.")
                            .font(UnigridStyle.prose)
                            .foregroundStyle(style.inkSecondary)
                        Link(destination: page) {
                            Label("Maps on nps.gov", systemImage: "arrow.up.right.square")
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
