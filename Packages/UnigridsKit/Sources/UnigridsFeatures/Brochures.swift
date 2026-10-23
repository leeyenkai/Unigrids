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
            do {
                return try await running.value
            } catch where !inexpensiveOnly {
                // The download already running may be a prefetch kept off cellular; one the
                // reader asked for is not, so it tries for itself.
                if let local = localFile(for: document) {
                    return local
                }
            }
        }
        let task = Task {
            try await download(document, for: placeID, inexpensiveOnly: inexpensiveOnly)
        }
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
