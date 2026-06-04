import CADCore

public enum SketchReference: Codable, Hashable, Sendable {
    case entity(SketchEntityID)
    case lineStart(SketchEntityID)
    case lineEnd(SketchEntityID)
    case circleCenter(SketchEntityID)
    case circleRadius(SketchEntityID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case entityID
    }

    private enum Kind: String, Codable {
        case entity
        case lineStart
        case lineEnd
        case circleCenter
        case circleRadius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        try container.validateOnlyExpectedKeys([.kind, .entityID], in: decoder)
        let entityID = try container.decode(SketchEntityID.self, forKey: .entityID)
        switch kind {
        case .entity:
            self = .entity(entityID)
        case .lineStart:
            self = .lineStart(entityID)
        case .lineEnd:
            self = .lineEnd(entityID)
        case .circleCenter:
            self = .circleCenter(entityID)
        case .circleRadius:
            self = .circleRadius(entityID)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entityID: SketchEntityID
        let kind: Kind
        switch self {
        case let .entity(id):
            entityID = id
            kind = .entity
        case let .lineStart(id):
            entityID = id
            kind = .lineStart
        case let .lineEnd(id):
            entityID = id
            kind = .lineEnd
        case let .circleCenter(id):
            entityID = id
            kind = .circleCenter
        case let .circleRadius(id):
            entityID = id
            kind = .circleRadius
        }
        try container.encode(kind, forKey: .kind)
        try container.encode(entityID, forKey: .entityID)
    }
}
