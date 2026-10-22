import Foundation
import UnigridsCore

extension Trip {
    /// Where the trip is on `date`: from its dates where it has them, else as set.
    public func status(
        on date: Date,
        calendar: Calendar = UnigridsCalendar.gregorian()
    ) -> TripStatus {
        TripStatus.on(date, start: startDate, end: endDate, stored: status, calendar: calendar)
    }
}

extension TripStop {
    /// What the stop is, read from and written to its stored fields. An unknown kind, or a
    /// lodging that has lost its position, reads as the place itself.
    public var target: StopTarget {
        get {
            let location = latitude.flatMap { latitude in
                longitude.map { Coordinate(latitude: latitude, longitude: $0) }
            }
            switch targetKindRaw {
            case "pointOfInterest": return targetID
                .map { .pointOfInterest(UnigridsID($0)) } ?? .place
            case "trail": return targetID.map { .trail(UnigridsID($0)) } ?? .place
            case "lodging":
                guard let location else { return .place }
                return .lodging(name: customName ?? "", location: location)
            case "custom":
                guard let location else { return .place }
                return .custom(name: customName ?? "", location: location)
            default: return .place
            }
        }
        set {
            targetKindRaw = newValue.kindRaw
            switch newValue {
            case .place:
                targetID = nil
                customName = nil
            case let .pointOfInterest(id), let .trail(id):
                targetID = id.rawValue
                customName = nil
            case let .lodging(name, location), let .custom(name, location):
                targetID = nil
                customName = name
                latitude = location.latitude
                longitude = location.longitude
            }
            if newValue.ownLocation == nil {
                latitude = nil
                longitude = nil
            }
        }
    }
}

extension Stamp {
    /// Whether the impression carries the America 250 seal, by the calendar day where it
    /// was made.
    public func hasAmerica250Seal(at place: Place?) -> Bool {
        hasAmerica250Seal(calendar: UnigridsCalendar.gregorian(at: place))
    }
}
