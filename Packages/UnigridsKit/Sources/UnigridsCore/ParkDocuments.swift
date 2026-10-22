import Foundation

/// An official PDF a park publishes: its Unigrid brochure, a park map, a trail or
/// campground map (SPECIFICATION.md §6, "Official brochure viewer").
///
/// Reference data holds the link, never the file. The app fetches the PDF from the NPS
/// the first time it is opened and keeps it on the device.
public struct ParkDocument: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable {
        case brochure
        case map
        case other

        public var name: String {
            switch self {
            case .brochure: "Official brochure"
            case .map: "Map"
            case .other: "Document"
            }
        }
    }

    public let title: String
    public let url: URL
    public let kind: Kind
    /// Size as the NPS server reported it when the link was last checked.
    public let bytes: Int?

    public var id: URL {
        url
    }

    public init(title: String, url: URL, kind: Kind, bytes: Int? = nil) {
        self.title = title
        self.url = url
        self.kind = kind
        self.bytes = bytes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        kind = (try? container.decode(Kind.self, forKey: .kind)) ?? .other
        bytes = try container.decodeIfPresent(Int.self, forKey: .bytes)
    }
}

/// A park's documents, and the maps page they were found on — where the app goes when a
/// park has no PDF it can show, or a stored link has broken.
public struct ParkDocuments: Hashable, Sendable, Codable {
    public let page: URL?
    public let documents: [ParkDocument]

    public init(page: URL?, documents: [ParkDocument]) {
        self.page = page
        self.documents = documents
    }

    /// The document to open first: the Unigrid brochure if there is one.
    public var primary: ParkDocument? {
        documents.first { $0.kind == .brochure } ?? documents.first
    }
}
