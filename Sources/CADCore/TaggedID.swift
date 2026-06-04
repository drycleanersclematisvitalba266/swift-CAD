import Foundation

public struct TaggedID<Tag>: Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue.uuidString
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UUID string for tagged ID."
            )
        }
        self.rawValue = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }
}
