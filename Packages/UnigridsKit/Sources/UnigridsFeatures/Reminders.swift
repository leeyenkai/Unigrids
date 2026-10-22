import MapKit
import Observation
import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference
import UserNotifications

// Reminders for permit lotteries, timed entry and booking windows (SPECIFICATION.md §10).

/// Local notifications for a trip's reminders — permit lotteries, timed-entry slots,
/// booking windows (§10). Scheduled on this device only; nothing leaves it.
///
/// A reminder fires at the moment it names, in the zone it was set in: a lottery that
/// opens at 07:00 in Utah opens then for a reader who has since flown east. The log is
/// the truth and notifications follow it — `reconcile` schedules what is missing and
/// removes what no reminder backs any more, so a deleted trip's reminders stop firing and
/// a reminder that arrived from another device starts.
@MainActor
enum ReminderScheduler {
    static let prefix = "reminder-"

    struct Request: Sendable {
        let id: UUID
        let title: String
        let body: String
        let date: Date
        let timeZone: TimeZone
        let link: String?
        let tripID: UUID?
    }

    static func request(for reminder: Reminder) -> Request {
        Request(
            id: reminder.id,
            title: reminder.title.isEmpty ? reminder.kind.name : reminder.title,
            body: "\(reminder.kind.name) for \(reminder.trip?.name ?? "your trip").",
            date: reminder.date,
            timeZone: reminder.timeZone,
            link: reminder.urlString,
            tripID: reminder.trip?.id
        )
    }

    /// Schedule one reminder, asking for permission if need be. False when it cannot be:
    /// notifications are off, or the moment has passed.
    @discardableResult
    static func schedule(_ reminder: Reminder) async -> Bool {
        await schedule(request(for: reminder), asking: true)
    }

    private static func schedule(_ request: Request, asking: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        if asking {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional,
            request.date > Date()
        else { return false }
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        var info: [String: String] = [NotificationRoute.key: NotificationRoute.reminder.rawValue]
        info["url"] = request.link
        info["trip"] = request.tripID?.uuidString
        content.userInfo = info
        // An absolute moment: the components carry the zone they were set in.
        var parts = UnigridsCalendar.gregorian(request.timeZone).dateComponents(
            [.year, .month, .day, .hour, .minute], from: request.date
        )
        parts.timeZone = request.timeZone
        let notification = UNNotificationRequest(
            identifier: prefix + request.id.uuidString,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        return await (try? center.add(notification)) != nil
    }

    static func cancel(_ ids: [UUID]) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids.map { prefix + $0.uuidString })
    }

    /// Make the pending notifications match the log, without asking for permission.
    static func reconcile(_ reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await Set(
            center.pendingNotificationRequests()
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
        )
        let wanted = reminders.filter { $0.date > Date() }
        let wantedIDs = Set(wanted.map { prefix + $0.id.uuidString })
        let stale = pending.subtracting(wantedIDs)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        for reminder in wanted where !pending.contains(prefix + reminder.id.uuidString) {
            _ = await schedule(request(for: reminder), asking: false)
        }
    }
}

/// A trip's reminders, and the way to add one. A reminder opens its editor; swiping it
/// away deletes it, with undo.
struct TripRemindersSection: View {
    @Environment(\.unigrid) private var style
    @Environment(\.modelContext) private var context
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let trip: Trip
    @State private var adding = false
    @State private var editing: Reminder?
    @State private var failure: String?

    private var reminders: [Reminder] {
        (trip.reminders ?? []).sorted { $0.date < $1.date }
    }

    var body: some View {
        Section {
            ForEach(reminders) { reminder in
                Button {
                    editing = reminder
                } label: {
                    ReminderRow(reminder: reminder)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button { editing = reminder } label: { Label("Edit", symbol: .edit) }
                    Button(role: .destructive) {
                        delete(reminder)
                    } label: {
                        Label("Delete", symbol: .delete)
                    }
                }
            }
            .onDelete { offsets in
                // Collected first: deleting while indexing the live list skips or overruns.
                offsets.map { reminders[$0] }.forEach(delete)
            }
            if let failure {
                ErrorLine(failure).listRowBackground(Color.clear)
            }
            Button {
                adding = true
            } label: {
                Label("Add a reminder", symbol: .addReminder)
            }
            .buttonStyle(BrochureButtonStyle(.secondary))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            ListNotes {
                FormNote(
                    "For permit lotteries, timed-entry slots and booking windows. Booking itself "
                        + "happens on Recreation.gov or the park's own site; Unigrids never handles it."
                )
            }
        } header: {
            SectionHead("Reminders", detail: reminders.isEmpty ? nil : "\(reminders.count)")
        }
        .unigridsSheet(isPresented: $adding) {
            ReminderEditor(trip: trip)
        }
        .unigridsSheet(item: $editing) { reminder in
            ReminderEditor(trip: trip, reminder: reminder)
        }
    }

    private func delete(_ reminder: Reminder) {
        ReminderScheduler.cancel([reminder.id])
        do {
            let change = try LogStore(context: context).delete(reminder: reminder)
            undo?.offer(change, message: change.summary { _ in nil })
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// A reminder in a trip's list: what for, and when, in the zone it was set in.
private struct ReminderRow: View {
    @Environment(\.unigrid) private var style
    let reminder: Reminder

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(reminder.date < Date() ? UnigridsSymbol.reminderPast : .reminder)
                .foregroundStyle(style.inkSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title.isEmpty ? reminder.kind.name : reminder.title)
                    .font(UnigridStyle.rowTitle)
                    .foregroundStyle(style.ink)
                Text(reminder.kind.name + " · " + ReminderEditor.when(
                    reminder.date,
                    in: reminder.timeZone
                ))
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.inkSecondary)
                if let url = reminder.url {
                    Link("Open booking page", destination: url)
                        .font(UnigridStyle.caption)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// Add or edit a reminder: what for, when — in the park's zone or this device's — and the
/// booking page it is about.
struct ReminderEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let trip: Trip
    var reminder: Reminder?

    @State private var kind = Reminder.Kind.permit
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400)
    @State private var atPark = true
    @State private var link = ""
    @State private var notice: String?
    @State private var saving = false

    /// The zone of the trip's first place: where a lottery or an entry slot is reckoned.
    private var parkZone: (name: String, zone: TimeZone)? {
        guard let place = trip.orderedStops.lazy.compactMap({ self.store.place($0.place) }).first
        else { return nil }
        return (place.name, UnigridsCalendar.gregorian(at: place).timeZone)
    }

    private var zone: TimeZone {
        atPark ? parkZone?.zone ?? .current : .current
    }

    /// "12 Jun 2026, 07:00 MDT".
    static func when(_ date: Date, in zone: TimeZone) -> String {
        let moment = date.formatted(UnigridsFormat.moment(in: UnigridsCalendar.gregorian(zone)))
        let abbreviation = zone.abbreviation(for: date) ?? zone.identifier
        return moment + " " + abbreviation
    }

    var body: some View {
        SheetPage(
            reminder == nil ? "New reminder" : "Reminder",
            kicker: trip.name,
            actions: .confirm(
                "Save",
                enabled: !saving,
                cancel: { dismiss() },
                action: { Task { await save() } }
            ),
            width: 480,
            height: 600
        ) {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(Reminder.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    TextField("What for — \"Angels Landing lottery opens\"", text: $title)
                } header: {
                    SectionHead("What")
                }
                Section {
                    DatePicker("When", selection: $date, in: Date()...)
                        .environment(\.timeZone, zone)
                    if let parkZone, parkZone.zone.identifier != TimeZone.current.identifier {
                        Picker("Time zone", selection: $atPark) {
                            Text("\(parkZone.name)'s").tag(true)
                            Text("This device's").tag(false)
                        }
                    }
                } header: {
                    SectionHead("When")
                } footer: {
                    FormNote("Alerts at \(Self.when(date, in: zone)), wherever you are then.")
                }
                Section {
                    TextField("Booking link (optional)", text: $link)
                        .textContentType(.URL)
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                    Link(
                        "Find it on Recreation.gov",
                        destination: URL(string: "https://www.recreation.gov/")
                            ?? URL(fileURLWithPath: "/")
                    )
                } header: {
                    SectionHead("Booking")
                }
                if reminder != nil {
                    Section {
                        Button(role: .destructive, action: delete) {
                            Label("Delete this reminder", symbol: .delete)
                        }
                    }
                }
                if let notice {
                    Section { FormNote(notice) }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let reminder else { return }
        kind = reminder.kind
        title = reminder.title
        date = reminder.date
        link = reminder.urlString ?? ""
        atPark = reminder.timeZone.identifier == parkZone?.zone.identifier
            || reminder.timeZone.identifier != TimeZone.current.identifier
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        let url = URL(string: link.trimmingCharacters(in: .whitespaces)).flatMap {
            $0.scheme == "https" || $0.scheme == "http" ? $0 : nil
        }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Reminder
        do {
            let log = LogStore(context: context)
            if let reminder {
                try log.update {
                    reminder.kind = kind
                    reminder.title = cleaned
                    reminder.date = date
                    reminder.urlString = url?.absoluteString
                    reminder.timeZoneID = zone.identifier
                }
                ReminderScheduler.cancel([reminder.id])
                saved = reminder
            } else {
                saved = try log.addReminder(
                    kind: kind, on: date, title: cleaned, url: url, timeZone: zone, to: trip
                )
            }
        } catch {
            notice = "It could not be saved: \(error.localizedDescription)"
            saving = false
            return
        }
        if await ReminderScheduler.schedule(saved) {
            dismiss()
        } else {
            notice = "Saved, but notifications are off for Unigrids, so it will not alert you. "
                + "Turn them on in Settings."
            try? await Task.sleep(for: .seconds(2.5))
            dismiss()
        }
    }

    private func delete() {
        guard let reminder else { return }
        ReminderScheduler.cancel([reminder.id])
        do {
            let change = try LogStore(context: context).delete(reminder: reminder)
            undo?.offer(change, message: change.summary { _ in nil })
            dismiss()
        } catch {
            notice = error.localizedDescription
        }
    }
}
