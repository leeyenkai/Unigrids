import CoreGraphics
import Foundation
import UnigridsCore

/// Launch arguments that put the app in a given state, for checking a screen by
/// screenshot on a simulator or a Mac without driving the interface by hand.
///
/// Debug builds only; a release build reads none of them. Pass as `-UnigridsDebugRegion
/// "36,-114,38,-111"` and so on — UserDefaults reads launch arguments as defaults.
enum DebugLaunch {
    #if DEBUG
        private static var defaults: UserDefaults {
            .standard
        }

        /// `south,west,north,east`
        static var region: BoundingBox? {
            guard let text = defaults.string(forKey: "UnigridsDebugRegion") else { return nil }
            let values = text.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { return nil }
            return BoundingBox(south: values[0], west: values[1], north: values[2], east: values[3])
        }

        static var selection: UnigridsID? {
            defaults.string(forKey: "UnigridsDebugSelect").map { UnigridsID($0) }
        }

        static var opens: UnigridsID? {
            defaults.string(forKey: "UnigridsDebugOpen").map { UnigridsID($0) }
        }

        static var showsKey: Bool {
            defaults.bool(forKey: "UnigridsDebugShowKey")
        }

        static var tab: String? {
            defaults.string(forKey: "UnigridsDebugTab")
        }

        static var explores: Bool {
            defaults.bool(forKey: "UnigridsDebugExplore")
        }

        /// A sight to open the explorer on.
        static var exploreSight: UnigridsID? {
            defaults.string(forKey: "UnigridsDebugExploreSight").map { UnigridsID($0) }
        }

        static var startsTour: Bool {
            defaults.bool(forKey: "UnigridsDebugTour")
        }

        static var opensFirstTrip: Bool {
            defaults.bool(forKey: "UnigridsDebugOpenTrip")
        }

        static var passportRegion: String? {
            defaults.string(forKey: "UnigridsDebugPassportRegion")
        }

        /// How far down to scroll a guide or leaflet, in points.
        static var scrollOffset: CGFloat? {
            let value = defaults.double(forKey: "UnigridsDebugScrollY")
            return value > 0 ? value : nil
        }
    #else
        static let region: BoundingBox? = nil
        static let selection: UnigridsID? = nil
        static let opens: UnigridsID? = nil
        static let showsKey = false
        static let tab: String? = nil
        static let explores = false
        static let exploreSight: UnigridsID? = nil
        static let startsTour = false
        static let scrollOffset: CGFloat? = nil
        static let opensFirstTrip = false
        static let passportRegion: String? = nil
    #endif
}
