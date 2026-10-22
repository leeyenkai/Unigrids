import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UnigridsCore
import UnigridsDesign
import UnigridsLog
import UnigridsReference

/// A trip stop read against the reference data: what it is called, where it is, and the
/// place it belongs to (SPECIFICATION.md §10: a stop can be a place, a sight, a trail,
/// lodging or any point on the way).
struct ResolvedStop: Identifiable {
    let stop: TripStop
    /// The place the stop belongs to — the park a sight is in, the park a motel is for.
    let place: Place?
    let title: String
    let subtitle: String
    /// Where the stop is: its own point, or its place's.
    let coordinate: Coordinate?

    var id: UUID {
        stop.id
    }

    /// The key drive times are kept under: one per point, not per stop, so two trips that
    /// share a leg route it once.
    var routeKey: String {
        switch stop.target {
        case .place: "place:\(stop.placeID)"
        case let .pointOfInterest(id): "poi:\(id.rawValue)"
        case let .trail(id): "trail:\(id.rawValue)"
        case let .lodging(_, location), let .custom(_, location):
            String(format: "point:%.5f,%.5f", location.latitude, location.longitude)
        }
    }

    /// The stop as the trip's schedule counts it.
    var scheduleID: UnigridsID {
        UnigridsID(stop.id.uuidString)
    }

    var symbol: UnigridsSymbol {
        switch stop.target {
        case .place: .map
        case .pointOfInterest: .checkIn
        case .trail: .distance
        case .lodging: .lodging
        case .custom: .waypoint
        }
    }

    init(_ stop: TripStop, store: any ReferenceStore) {
        self.stop = stop
        let place = store.place(stop.place)
        self.place = place
        switch stop.target {
        case .place:
            title = place?.name ?? "Unknown place"
            subtitle = place.map { "\($0.designation) · \($0.statesDescription)" }
                ?? stop.placeID
            coordinate = place?.centre
        case let .pointOfInterest(id):
            let poi = store.pointsOfInterest(in: stop.place).first { $0.id == id }
            title = poi?.name ?? "Unknown sight"
            subtitle = [poi?.kind.name, place.map { "in \($0.name)" }]
                .compactMap(\.self).joined(separator: " ")
            coordinate = poi?.location ?? place?.centre
        case let .trail(id):
            let trail = store.trails(in: stop.place).first { $0.id == id }
            title = trail?.name ?? "Unknown trail"
            subtitle = "Trail" + (place.map { " in \($0.name)" } ?? "")
            coordinate = trail?.start ?? place?.centre
        case let .lodging(name, location):
            title = name.isEmpty ? "Lodging" : name
            subtitle = "Lodging" + (place.map { " for \($0.name)" } ?? "")
            coordinate = location
        case let .custom(name, location):
            title = name.isEmpty ? "A stop" : name
            subtitle = place.map { "On the way to \($0.name)" } ?? "A point on the way"
            coordinate = location
        }
    }

    /// Where routing starts or ends: a park's visitor centre facing the other end, since
    /// a park's centre can be twenty miles from a road; any other stop's own point.
    func routeAnchor(toward point: Coordinate, store: any ReferenceStore) -> Coordinate? {
        guard case .place = stop.target, let place else { return coordinate }
        return store.visitorCentres(in: place.id)
            .min { $0.location.distance(to: point) < $1.location.distance(to: point) }?
            .location ?? place.centre
    }
}

// MARK: - Exports

/// A trip's stops as an iCalendar file, written only when it is shared.
struct TripCalendarFile: Transferable {
    let name: String
    let identifier: String
    let events: [TripCalendar.Event]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .calendarEvent) { file in
            Data(
                TripCalendar.document(
                    name: file.name, events: file.events, identifier: file.identifier, stamp: Date()
                ).utf8
            )
        }
        .suggestedFileName { "\($0.name.fileStem).ics" }
    }
}

/// A trip's stops as GPX waypoints, for any mapping app, written only when it is shared.
struct TripGPXFile: Transferable {
    let name: String
    let waypoints: [TripGPX.Waypoint]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType(filenameExtension: "gpx") ?? .xml) { file in
            Data(TripGPX.document(name: file.name, waypoints: file.waypoints).utf8)
        }
        .suggestedFileName { "\($0.name.fileStem).gpx" }
    }
}

extension String {
    /// "Utah-in-April": a name safe for a file.
    var fileStem: String {
        let stem = components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return stem.isEmpty ? "trip" : stem
    }
}

extension ResolvedStop {
    /// The calendar event for a dated stop.
    func calendarEvent(calendar: Calendar) -> TripCalendar.Event? {
        guard let day = stop.plannedDate else { return nil }
        let title = switch stop.target {
        case .place:
            [place?.name ?? title, place?.designation ?? ""].joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        default:
            title + (place.map { " — \($0.name)" } ?? "")
        }
        return TripCalendar.Event(
            uid: stop.id.uuidString,
            title: title,
            day: day,
            time: stop.isTimed ? day : nil,
            notes: stop.notes
        )
    }

    var waypoint: TripGPX.Waypoint? {
        guard let coordinate else { return nil }
        return TripGPX.Waypoint(
            name: title, coordinate: coordinate, date: stop.plannedDate, note: stop.notes
        )
    }
}
