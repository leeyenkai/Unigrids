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

/// A trip's reminders, and the way to add one.
struct TripRemindersSection: View {
    @Environment(\.unigrid) private var style
    @Environment(\.modelContext) private var context
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    let trip: Trip
    @State private var adding = false
    @State private var failure: String?

    private var reminders: [Reminder] {
        (trip.reminders ?? []).sorted { $0.date < $1.date }
    }

    var body: some View {
        Section {
            ForEach(reminders) { reminder in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: reminder.date < Date() ? "bell.slash" : "bell")
                        .foregroundStyle(style.inkSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title.isEmpty ? reminder.kind.name : reminder.title)
                            .font(UnigridStyle.rowTitle)
                            .foregroundStyle(style.ink)
                        Text(
                            reminder.kind.name + " · "
                                + reminder.date.formatted(date: .abbreviated, time: .shortened)
                        )
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                        if let url = reminder.url {
                            Link("Open booking page", destination: url)
                                .font(UnigridStyle.caption)
                        }
                    }
                }
                .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                // Collected first: deleting while indexing the live list skips or overruns.
                let doomed = offsets.map { reminders[$0] }
                for reminder in doomed {
                    ReminderScheduler.cancel([reminder.id])
                    do {
                        let change = try LogStore(context: context).delete(reminder: reminder)
                        undo?.offer(change, message: change.summary { _ in nil })
                    } catch {
                        failure = error.localizedDescription
                    }
                }
            }
            Button {
                adding = true
            } label: {
                Label("Add a reminder", systemImage: "bell.badge")
            }
            .buttonStyle(BrochureButtonStyle(.secondary))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        } header: {
            SectionHead("Reminders", detail: reminders.isEmpty ? nil : "\(reminders.count)")
        } footer: {
            Text(
                "For permit lotteries, timed-entry slots and booking windows. Booking itself "
                    + "happens on Recreation.gov or the park's own site; Unigrids never handles it."
            )
            .font(UnigridStyle.caption)
        }
        .unigridsSheet(isPresented: $adding) {
            ReminderEditor(trip: trip)
        }
    }
}

struct ReminderEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var kind = Reminder.Kind.permit
    @State private var title = ""
    @State private var date = Date().addingTimeInterval(86400)
    @State private var link = ""
    @State private var notice: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(Reminder.Kind.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                TextField("What for — \"Angels Landing lottery opens\"", text: $title)
                DatePicker("When", selection: $date, in: Date()...)
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
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reminder")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
        }
        .sheetSize(width: 460, height: 480)
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        let url = URL(string: link.trimmingCharacters(in: .whitespaces)).flatMap {
            $0.scheme == "https" || $0.scheme == "http" ? $0 : nil
        }
        let reminder: Reminder
        do {
            reminder = try LogStore(context: context).addReminder(
                kind: kind, on: date, title: title, url: url, to: trip
            )
        } catch {
            notice = "It could not be saved: \(error.localizedDescription)"
            saving = false
            return
        }
        if await ReminderScheduler.schedule(reminder) {
            dismiss()
        } else {
            notice = "Saved, but notifications are off for Unigrids, so it will not alert you. "
                + "Turn them on in Settings."
            try? await Task.sleep(for: .seconds(2.5))
            dismiss()
        }
    }
}
