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
@MainActor
enum ReminderScheduler {
    static func schedule(_ reminder: Reminder, tripName: String) async -> Bool {
        // Read off the model here, on the main actor; only plain values go to the
        // notification centre.
        let identifier = identifier(reminder)
        let title = reminder.title.isEmpty ? reminder.kind.name : reminder.title
        let body = "\(reminder.kind.name) for \(tripName)."
        let date = reminder.date
        let link = reminder.urlString
        return await schedule(
            identifier: identifier,
            title: title,
            body: body,
            date: date,
            link: link
        )
    }

    private static func schedule(
        identifier: String, title: String, body: String, date: Date, link: String?
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = await (try? center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted, date > Date() else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let link {
            content.userInfo = ["url": link]
        }
        let parts = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        return await (try? center.add(request)) != nil
    }

    static func cancel(_ reminder: Reminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(reminder)])
    }

    private static func identifier(_ reminder: Reminder) -> String {
        "reminder-\(reminder.id.uuidString)"
    }
}

/// A trip's reminders, and the way to add one.
struct TripRemindersSection: View {
    @Environment(\.unigrid) private var style
    @Environment(\.modelContext) private var context
    let trip: Trip
    @State private var adding = false

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
                for offset in offsets {
                    ReminderScheduler.cancel(reminders[offset])
                    try? LogStore(context: context).delete(reminders[offset])
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
        .sheet(isPresented: $adding) {
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
                }
            }
        }
        .sheetSize(width: 460, height: 480)
    }

    private func save() async {
        let url = URL(string: link.trimmingCharacters(in: .whitespaces)).flatMap {
            $0.scheme == "https" || $0.scheme == "http" ? $0 : nil
        }
        let reminder = Reminder(kind: kind, date: date, title: title, url: url, trip: trip)
        context.insert(reminder)
        try? context.save()
        if await ReminderScheduler.schedule(reminder, tripName: trip.name) {
            dismiss()
        } else {
            notice = "Saved, but notifications are off for Unigrids, so it will not alert you. "
                + "Turn them on in Settings."
            try? await Task.sleep(for: .seconds(2.5))
            dismiss()
        }
    }
}
