import CADCore

public enum Surface3D: Codable, Sendable, Hashable {
    case plane(Plane3D)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
        }
    }

    public var uDomain: ParameterDomain {
        switch self {
        case .plane:
            .unbounded
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case .plane:
            .unbounded
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case plane
    }

    private enum Kind: String, Codable {
        case plane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .plane:
            try container.validateOnlyExpectedKeys([.kind, .plane], in: decoder)
            self = .plane(try container.decode(Plane3D.self, forKey: .plane))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plane(plane):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(plane, forKey: .plane)
        }
    }
}
