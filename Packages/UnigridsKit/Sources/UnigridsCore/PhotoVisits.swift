import Foundation

/// Finds which place a point is in, fast enough to ask for every photo in a library.
///
/// A coarse grid of one-degree cells holds each outline's id in every cell its box
/// touches, so a point is tested only against the handful of outlines near it rather
/// than against all of them.
public struct PlaceLocator: Sendable {
    private let boundaries: [UnigridsID: PlaceBoundary]
    private let cells: [Int: [UnigridsID]]

    public init(boundaries: [UnigridsID: PlaceBoundary]) {
        self.boundaries = boundaries
        var cells: [Int: [UnigridsID]] = [:]
        for (id, boundary) in boundaries {
            let box = boundary.extent
            // A box wider than a few dozen cells is an Alaskan giant; it still only
            // needs indexing where it is.
            for lat in stride(from: Int(floor(box.south)), through: Int(floor(box.north)), by: 1) {
                for lon in stride(
                    from: Int(floor(box.west)),
                    through: Int(floor(box.east)),
                    by: 1
                ) {
                    cells[Self.cell(lat, lon), default: []].append(id)
                }
            }
        }
        self.cells = cells
    }

    /// The smallest outline holding the point, as a tap on the map would choose.
    public func place(at point: Coordinate) -> UnigridsID? {
        let key = Self.cell(Int(floor(point.latitude)), Int(floor(point.longitude)))
        return (cells[key] ?? [])
            .compactMap { id -> (UnigridsID, Double)? in
                guard let boundary = boundaries[id], boundary.contains(point) else { return nil }
                return (id, boundary.extent.degreeArea)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func cell(_ lat: Int, _ lon: Int) -> Int {
        (lat + 90) * 1000 + (lon + 180)
    }
}

/// A photo as the import sees it: an identifier, when, and where.
public struct GeoPhoto: Hashable, Sendable {
    public let id: String
    public let date: Date
    public let location: Coordinate

    public init(id: String, date: Date, location: Coordinate) {
        self.id = id
        self.date = date
        self.location = location
    }
}

/// A visit the photo library suggests: a place, a day, and the photos taken there.
public struct ProposedVisit: Hashable, Sendable, Identifiable {
    public let placeID: UnigridsID
    public let day: Date
    public let photoIDs: [String]
    public let first: Date
    public let last: Date

    public var id: String {
        "\(placeID.rawValue)@\(day.timeIntervalSince1970)"
    }
}

/// Visits close together in time, suggested as one trip.
public struct ProposedTrip: Hashable, Sendable, Identifiable {
    public let visits: [ProposedVisit]

    public var id: String {
        visits.map(\.id).joined(separator: "|")
    }

    public var start: Date {
        visits.first?.day ?? Date()
    }

    public var end: Date {
        visits.last?.day ?? Date()
    }
}

/// Photo import (SPECIFICATION.md §9): "an on-device scan of geotagged photos that fall
/// inside park boundaries, grouped by date into proposed visits and trips for the user to
/// accept, edit or discard."
public enum PhotoVisits {
    /// Visits the photos suggest: one per place per day, leaving out days already logged.
    public static func propose(
        photos: [GeoPhoto],
        locator: PlaceLocator,
        alreadyLogged: Set<String> = [],
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> [ProposedVisit] {
        struct Group {
            let place: UnigridsID
            let day: Date
            var photos: [GeoPhoto] = []
        }
        var grouped: [String: Group] = [:]
        for photo in photos {
            guard let place = locator.place(at: photo.location) else { continue }
            let day = calendar.startOfDay(for: photo.date)
            let key = loggedKey(place, day)
            guard !alreadyLogged.contains(key) else { continue }
            grouped[key, default: Group(place: place, day: day)].photos.append(photo)
        }
        return grouped.values
            .map { group in
                let sorted = group.photos.sorted { $0.date < $1.date }
                return ProposedVisit(
                    placeID: group.place,
                    day: group.day,
                    photoIDs: sorted.map(\.id),
                    first: sorted.first?.date ?? group.day,
                    last: sorted.last?.date ?? group.day
                )
            }
            .sorted { ($0.day, $0.first) < ($1.day, $1.first) }
    }

    /// Group visits into trips wherever no more than `gapDays` separate one from the next.
    public static func trips(
        from visits: [ProposedVisit],
        gapDays: Int = 2,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> [ProposedTrip] {
        var trips: [[ProposedVisit]] = []
        for visit in visits.sorted(by: { ($0.day, $0.first) < ($1.day, $1.first) }) {
            let gap = trips.last?.last.flatMap {
                calendar.dateComponents([.day], from: $0.day, to: visit.day).day
            }
            if let gap, gap <= gapDays {
                trips[trips.count - 1].append(visit)
            } else {
                trips.append([visit])
            }
        }
        return trips.map(ProposedTrip.init(visits:))
    }

    /// The key a logged visit is matched on: place and calendar day.
    public static func loggedKey(_ place: UnigridsID, _ day: Date) -> String {
        "\(place.rawValue)@\(Int(day.timeIntervalSince1970))"
    }
}
