public enum FeatureOperation: Codable, Sendable {
    case sketch(Sketch)
    case extrude(ExtrudeFeature)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sketch
        case extrude
    }

    private enum Kind: String, Codable {
        case sketch
        case extrude
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .sketch:
            try container.validateOnlyExpectedKeys([.kind, .sketch], in: decoder)
            self = .sketch(try container.decode(Sketch.self, forKey: .sketch))
        case .extrude:
            try container.validateOnlyExpectedKeys([.kind, .extrude], in: decoder)
            self = .extrude(try container.decode(ExtrudeFeature.self, forKey: .extrude))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .sketch(sketch):
            try container.encode(Kind.sketch, forKey: .kind)
            try container.encode(sketch, forKey: .sketch)
        case let .extrude(extrude):
            try container.encode(Kind.extrude, forKey: .kind)
            try container.encode(extrude, forKey: .extrude)
        }
    }
}
