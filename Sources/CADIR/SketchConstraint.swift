import CADCore

public enum SketchConstraint: Codable, Sendable, Hashable {
    case coincident(SketchReference, SketchReference)
    case horizontal(SketchEntityID)
    case vertical(SketchEntityID)
    case parallel(SketchEntityID, SketchEntityID)
    case perpendicular(SketchEntityID, SketchEntityID)
    case fixed(SketchReference)

    private enum CodingKeys: String, CodingKey {
        case kind
        case first
        case second
        case entityID
    }

    private enum Kind: String, Codable {
        case coincident
        case horizontal
        case vertical
        case parallel
        case perpendicular
        case fixed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .coincident:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .coincident(
                try container.decode(SketchReference.self, forKey: .first),
                try container.decode(SketchReference.self, forKey: .second)
            )
        case .horizontal:
            try container.validateOnlyExpectedKeys([.kind, .entityID], in: decoder)
            self = .horizontal(try container.decode(SketchEntityID.self, forKey: .entityID))
        case .vertical:
            try container.validateOnlyExpectedKeys([.kind, .entityID], in: decoder)
            self = .vertical(try container.decode(SketchEntityID.self, forKey: .entityID))
        case .parallel:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .parallel(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .perpendicular:
            try container.validateOnlyExpectedKeys([.kind, .first, .second], in: decoder)
            self = .perpendicular(
                try container.decode(SketchEntityID.self, forKey: .first),
                try container.decode(SketchEntityID.self, forKey: .second)
            )
        case .fixed:
            try container.validateOnlyExpectedKeys([.kind, .first], in: decoder)
            self = .fixed(try container.decode(SketchReference.self, forKey: .first))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .coincident(first, second):
            try container.encode(Kind.coincident, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .horizontal(entityID):
            try container.encode(Kind.horizontal, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case let .vertical(entityID):
            try container.encode(Kind.vertical, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
        case let .parallel(first, second):
            try container.encode(Kind.parallel, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .perpendicular(first, second):
            try container.encode(Kind.perpendicular, forKey: .kind)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        case let .fixed(reference):
            try container.encode(Kind.fixed, forKey: .kind)
            try container.encode(reference, forKey: .first)
        }
    }
}
