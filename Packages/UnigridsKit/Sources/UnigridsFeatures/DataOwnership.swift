import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// Settings › Your data: what the log holds, a backup out, a backup in, and a way to
/// clear it all (SPECIFICATION.md §9, "Ownership of data").
///
/// Exports are written when asked for, not whenever the screen draws. Importing merges by
/// record identifier, so a backup restored twice, or into a log that already holds some of
/// it, adds nothing twice.
struct YourDataSection: View {
    @Environment(\.referenceStore) private var store
    @Environment(\.modelContext) private var context
    @Environment(\.unigrid) private var style

    @Query private var visits: [Visit]
    @Query private var stamps: [Stamp]
    @Query private var trips: [Trip]
    @Query private var reminders: [Reminder]

    @State private var exported: ExportedFiles?
    @State private var importing = false
    @State private var confirmingErase = false
    @State private var message: String?

    var body: some View {
        Section {
            HStack(spacing: 12) {
                FigureBlock(value: visits.count.formatted(), label: "Visits", compact: true)
                FigureBlock(value: stamps.count.formatted(), label: "Stamps", compact: true)
                FigureBlock(value: trips.count.formatted(), label: "Trips", compact: true)
            }
            .listRowBackground(Color.clear)

            if let exported {
                ShareLink(item: exported.json) {
                    Label("Share the backup (JSON)", symbol: .share)
                }
                ShareLink(item: exported.csv) {
                    Label("Share visits (CSV)", symbol: .spreadsheet)
                }
            } else {
                Button {
                    export()
                } label: {
                    Label("Export a backup", symbol: .share)
                }
            }
            Button {
                importing = true
            } label: {
                Label("Import a backup", symbol: .importFile)
            }
            Button(role: .destructive) {
                confirmingErase = true
            } label: {
                Label("Delete all my data", symbol: .delete)
            }
            .disabled(visits.isEmpty && stamps.isEmpty && trips.isEmpty)

            if let message {
                Text(message)
                    .font(UnigridStyle.caption)
                    .foregroundStyle(style.ink)
            }
            Text(
                "Your log is kept on this device. There are no accounts and no servers, so "
                    + "the developer never holds any of it. Export a backup to keep a copy of "
                    + "your own; importing one adds what this device does not already have."
            )
            .font(UnigridStyle.caption)
            .foregroundStyle(style.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            SectionHead("Your data")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .confirmationDialog(
            "Delete every trip, visit and stamp?",
            isPresented: $confirmingErase,
            titleVisibility: .visible
        ) {
            Button("Delete all my data", role: .destructive, action: erase)
        } message: {
            Text("This cannot be undone. Export a backup first if you might want it back.")
        }
    }

    private func export() {
        do {
            let archive = try LogArchive.of(
                context,
                name: { store.place($0)?.name },
                calendar: { UnigridsCalendar.gregorian(at: store.place($0)) }
            )
            let folder = FileManager.default.temporaryDirectory
            let stamp = Date().formatted(.iso8601.year().month().day())
            let json = folder.appending(path: "Unigrids backup \(stamp).json")
            let csv = folder.appending(path: "Unigrids visits \(stamp).csv")
            try archive.json().write(to: json, options: .atomic)
            try LogExport.visitsCSV(archive) { UnigridsCalendar.gregorian(at: store.place($0)) }
                .write(to: csv, atomically: true, encoding: .utf8)
            exported = ExportedFiles(json: json, csv: csv)
            message = nil
        } catch {
            message = "The backup could not be written: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, any Error>) {
        let archive: LogArchive
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            archive = try LogArchive.decode(Data(contentsOf: url))
        } catch {
            message = "That file could not be read as a Unigrids backup."
            return
        }
        do {
            let summary = try LogStore(context: context).merge(archive) {
                UnigridsCalendar.gregorian(at: store.place($0))
            }
            message = Self.describe(summary)
            exported = nil
            Task { await ReminderScheduler.reconcile(reminders) }
        } catch {
            // The backup read fine; the log could not take it. Nothing was added.
            message = "The backup could not be added: \(error.localizedDescription)"
        }
    }

    /// "Added 3 visits, 1 trip and 12 other records."
    private static func describe(_ summary: MergeSummary) -> String {
        guard summary.added > 0 else {
            return "Nothing new: this device already has everything in that backup."
        }
        let parts = [
            (summary.visitsAdded, "visit"),
            (summary.tripsAdded, "trip"),
            (summary.stampsAdded, "stamp"),
            (summary.othersAdded, "other record"),
        ]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }
        return "Added " + ListFormatter.localizedString(byJoining: parts) + "."
    }

    private func erase() {
        do {
            ReminderScheduler.cancel(reminders.map(\.id))
            try LogStore(context: context).eraseEverything()
            exported = nil
            message = "Your log is empty."
        } catch {
            message = "Not everything could be deleted: \(error.localizedDescription)"
        }
    }
}

private struct ExportedFiles: Equatable {
    let json: URL
    let csv: URL
}
