import SwiftData
import SwiftUI
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference
#if os(iOS)
    import UIKit
#endif

/// The stamp sheet (SPECIFICATION.md §9).
///
/// Asks for the date and, where a site has more than one official cancellation location,
/// which one. Press and hold to stamp — the gesture is the point, and the haptic thump
/// and ink settle that follow it are what makes it feel like a stamp rather than a form.
/// VoiceOver and keyboard users stamp with the control's action instead.
public struct StampSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.referenceStore) private var store
    @Environment(\.unigrid) private var style
    @Environment(UndoCenter.self) private var undo: UndoCenter?
    @Environment(\.undoHost) private var undoHost

    let place: Place

    @State private var date: Date
    @State private var stampLocationID: UnigridsID?
    @State private var realStampCollected = false
    @State private var stamped: Stamp?
    @State private var checking = false
    @State private var error: String?
    @State private var onSite = OnSiteCheck()

    /// Defaults to today, or to the visit's date when stamping from a visit.
    public init(place: Place, suggestedDate: Date = Date()) {
        self.place = place
        _date = State(initialValue: suggestedDate)
    }

    /// The sheet for one of a site's stamp locations, chosen from its passport slot.
    init(place: Place, location: UnigridsID?) {
        self.init(place: place)
        _stampLocationID = State(initialValue: location)
    }

    private var stampLocations: [PointOfInterest] {
        store.stampLocations(in: place.id)
    }

    private var region: PassportRegion {
        place.resolvedPassportRegion
    }

    /// Days at the place, in its own zone (SPECIFICATION.md §9: the America 250 rule
    /// follows the stamp's date).
    private var calendar: Calendar {
        UnigridsCalendar.gregorian(at: place)
    }

    private func face(seed: UInt64, date: Date, verified: Bool) -> StampFace {
        StampFace(
            siteName: place.name,
            date: date,
            stateCode: place.states.first?.code ?? "US",
            region: region,
            seed: seed,
            isVerifiedOnSite: verified,
            calendar: calendar
        )
    }

    public var body: some View {
        SheetPage(
            stamped == nil ? "Stamp" : "Stamped",
            kicker: place.name,
            actions: stamped == nil ? .cancel { dismiss() } : .done { dismiss() },
            width: 520,
            height: 700
        ) {
            ScrollView {
                VStack(spacing: 24) {
                    if let stamped {
                        stampedResult(stamped)
                    } else {
                        preview
                        controls
                    }
                }
                .padding(24)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            // A fixed preview seed: the real impression gets its own when it is saved, so
            // the preview does not pretend to be the exact impression you will get.
            StampView(face: face(seed: 0xC0FF_EE00, date: date, verified: false), diameter: 150)
            Kicker("\(region.name) region")
            if America250.applies(to: date, calendar: calendar) {
                Label {
                    Text("Dated in 2026 — this impression gets the America 250 seal")
                } icon: {
                    Image(.commemorativeOutline)
                }
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.seal)
                .multilineTextAlignment(.center)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 18) {
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .environment(\.timeZone, calendar.timeZone)
                .font(UnigridStyle.rowTitle)

            if stampLocations.count > 1 {
                Picker("Stamp location", selection: $stampLocationID) {
                    Text("Not specified").tag(UnigridsID?.none)
                    ForEach(stampLocations) { location in
                        Text(location.name).tag(UnigridsID?.some(location.id))
                    }
                }
                .pickerStyle(.menu)
                .font(UnigridStyle.rowTitle)
            }

            Toggle("I collected the paper cancellation too", isOn: $realStampCollected)
                .font(UnigridStyle.rowTitle)

            if checking {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Checking you're on site…")
                        .font(UnigridStyle.rowDetail)
                        .foregroundStyle(style.inkSecondary)
                }
            } else {
                StampHoldButton { save() }
            }

            if let error {
                Label {
                    Text(error)
                } icon: {
                    Image(.warning)
                }
                .font(UnigridStyle.rowDetail)
                .foregroundStyle(style.ink)
            }
        }
    }

    private func stampedResult(_ stamp: Stamp) -> some View {
        VStack(spacing: 16) {
            StampView(
                face: face(seed: stamp.seed, date: stamp.date, verified: stamp.isVerifiedOnSite),
                diameter: 170
            )
            Text(
                stamp.isVerifiedOnSite
                    ? "Stamped on site. Added to your passport and your log."
                    : "Added to your passport and your log."
            )
            .font(UnigridStyle.proseSmall)
            .foregroundStyle(style.inkSecondary)
            .multilineTextAlignment(.center)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func save() {
        guard stamped == nil, !checking else { return }
        let log = LogStore(context: context)
        let today = UnigridsCalendar.isSameDay(date, Date(), calendar: calendar)
        // Today is stamped at this moment; another day at noon there, so it reads as that
        // day wherever it is read.
        let stampDate = today ? Date()
            : UnigridsCalendar.noon(onDayOf: date, shownIn: calendar, in: calendar)
        Task {
            // Only a stamp dated today can have been made on site, so only then is the
            // reader's location asked for (SPECIFICATION.md §9, §15), and for no more
            // than a few seconds.
            var verified = false
            if today {
                checking = true
                verified = await onSite.isOnSite(at: place, boundary: store.boundary(for: place.id))
                checking = false
            }
            do {
                let madeVisit = try log
                    .visit(to: place.id, on: stampDate, calendar: calendar) == nil
                let stamp = try log.stamp(
                    place.id,
                    at: stampLocationID,
                    on: stampDate,
                    verifiedOnSite: verified,
                    realStampCollected: realStampCollected,
                    calendar: calendar
                )
                #if os(iOS)
                    // The haptic thump §9 asks for.
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                #endif
                withAnimation(.spring(duration: 0.4)) { stamped = stamp }
                undo?.offer(
                    log.undoing(stamp: stamp, madeVisit: madeVisit),
                    message: "Stamped \(place.name)",
                    from: undoHost
                )
            } catch {
                self.error = "This stamp could not be saved: \(error.localizedDescription)"
            }
        }
    }
}

/// Press and hold to stamp: the square fills as the press goes on, and the stamp lands
/// when it is full. A tap only says to keep holding. VoiceOver's activate and the
/// keyboard's Space stamp at once — the hold is a feel, not a test.
private struct StampHoldButton: View {
    @Environment(\.unigrid) private var style
    let onStamp: () -> Void
    @State private var pressing = false
    @State private var hint = false

    private let duration = 0.6

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Rectangle().fill(style.ink.opacity(0.15))
                GeometryReader { proxy in
                    Rectangle()
                        .fill(style.ink)
                        .frame(width: pressing ? proxy.size.width : 0)
                        .animation(
                            pressing ? .linear(duration: duration) : .easeOut(duration: 0.15),
                            value: pressing
                        )
                }
                Label { Text("Stamp") } icon: { StampIcon(isFilled: true) }
                    .font(UnigridStyle.action)
                    .foregroundStyle(pressing ? style.page : style.ink)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 50)
            .overlay { Rectangle().strokeBorder(style.ink, lineWidth: 1.2) }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration) {
                onStamp()
            } onPressingChanged: { isPressing in
                pressing = isPressing
            }
            .simultaneousGesture(TapGesture().onEnded { hint = true })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stamp")
            .accessibilityHint("Press and hold, or activate, to stamp the passport.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onStamp() }
            .focusable()
            .onKeyPress(.space) {
                onStamp()
                return .handled
            }

            Text(hint ? "Keep holding until the bar fills." : "Press and hold to stamp.")
                .font(UnigridStyle.caption)
                .foregroundStyle(style.inkSecondary)
        }
    }
}
