import Foundation

/// The encoded-polyline format, at five decimal places.
///
/// Park outlines ship as these strings rather than as JSON arrays of numbers: a ring of a
/// thousand points is about five kilobytes encoded against twenty-odd as `[[lat, lon]]`,
/// and decoding a string is a tight loop where decoding nested arrays through `Codable`
/// allocates a value per number. Five decimal places is about a metre, far finer than the
/// outlines are generalised to.
///
/// The algorithm is the widely used one: each coordinate is stored as the delta from the
/// previous one, zig-zag encoded, and written in five-bit chunks offset into printable
/// ASCII.
public enum Polyline {
    /// Decimal places kept. 1e5 is the format's common precision.
    public static let precision: Double = 1e5

    /// The coordinates in an encoded string. Malformed input yields the points decoded
    /// before the fault rather than throwing: a broken outline is a missing outline, not
    /// a crash.
    public static func decode(_ encoded: String) -> [Coordinate] {
        var coordinates: [Coordinate] = []
        var latitude = 0
        var longitude = 0
        var iterator = encoded.utf8.makeIterator()

        while true {
            guard let deltaLatitude = nextValue(&iterator),
                  let deltaLongitude = nextValue(&iterator) else { break }
            latitude += deltaLatitude
            longitude += deltaLongitude
            coordinates.append(Coordinate(
                latitude: Double(latitude) / precision,
                longitude: Double(longitude) / precision
            ))
        }
        return coordinates
    }

    /// The encoded form of some coordinates. The pipeline is the real encoder; this exists
    /// so the round trip can be tested and so previews can build outlines in code.
    public static func encode(_ coordinates: [Coordinate]) -> String {
        var output = ""
        var previousLatitude = 0
        var previousLongitude = 0
        for coordinate in coordinates {
            let latitude = Int((coordinate.latitude * precision).rounded())
            let longitude = Int((coordinate.longitude * precision).rounded())
            append(latitude - previousLatitude, to: &output)
            append(longitude - previousLongitude, to: &output)
            previousLatitude = latitude
            previousLongitude = longitude
        }
        return output
    }

    private static func nextValue(_ iterator: inout String.UTF8View.Iterator) -> Int? {
        var result = 0
        var shift = 0
        while let byte = iterator.next() {
            guard byte >= 63 else { return nil }
            let chunk = Int(byte) - 63
            result |= (chunk & 0x1F) << shift
            shift += 5
            if chunk < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
            // More than 32 bits of payload means the string is not a polyline.
            guard shift < 35 else { return nil }
        }
        return nil
    }

    private static func append(_ value: Int, to output: inout String) {
        var remaining = value < 0 ? ~(value << 1) : (value << 1)
        while remaining >= 0x20 {
            output.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (remaining & 0x1F)) + 63)))
            remaining >>= 5
        }
        output.unicodeScalars.append(UnicodeScalar(UInt8(remaining + 63)))
    }
}
