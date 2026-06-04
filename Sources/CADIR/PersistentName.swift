import CADCore

public struct PersistentName: Hashable, Codable, Sendable {
    public var components: [NameComponent]

    public init(components: [NameComponent]) {
        self.components = components
    }

    public func validate() throws {
        guard !components.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Persistent name must contain at least one component.")
        }
        for component in components {
            try component.validate()
        }
    }
}

public enum GeneratedSubshapeRole: String, Codable, Sendable, Hashable {
    case body
    case vertex
    case edge
    case startFace
    case endFace
    case sideFace
}

public enum NameComponent: Hashable, Codable, Sendable {
    case feature(FeatureID)
    case generated(String)
    case subshape(String)
    case index(Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case featureID
        case value
        case index
    }

    private enum Kind: String, Codable {
        case feature
        case generated
        case subshape
        case index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .feature:
            try container.validateOnlyExpectedKeys([.kind, .featureID], in: decoder)
            self = .feature(try container.decode(FeatureID.self, forKey: .featureID))
        case .generated:
            try container.validateOnlyExpectedKeys([.kind, .value], in: decoder)
            self = .generated(try container.decode(String.self, forKey: .value))
        case .subshape:
            try container.validateOnlyExpectedKeys([.kind, .value], in: decoder)
            self = .subshape(try container.decode(String.self, forKey: .value))
        case .index:
            try container.validateOnlyExpectedKeys([.kind, .index], in: decoder)
            self = .index(try container.decode(Int.self, forKey: .index))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .feature(featureID):
            try container.encode(Kind.feature, forKey: .kind)
            try container.encode(featureID, forKey: .featureID)
        case let .generated(value):
            try container.encode(Kind.generated, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .subshape(value):
            try container.encode(Kind.subshape, forKey: .kind)
            try container.encode(value, forKey: .value)
        case let .index(index):
            try container.encode(Kind.index, forKey: .kind)
            try container.encode(index, forKey: .index)
        }
    }

    public func validate() throws {
        switch self {
        case .feature:
            return
        case let .generated(value):
            guard !value.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Generated persistent name component must not be empty.")
            }
        case let .subshape(value):
            guard !value.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Subshape persistent name component must not be empty.")
            }
        case let .index(index):
            guard index >= 0 else {
                throw FeatureEvaluationError.invalidGraph("Persistent name index component must not be negative.")
            }
        }
    }
}

public struct PersistentNameMap: Codable, Sendable, Equatable {
    public var entries: [PersistentName: TopologyReference]

    public init(_ entries: [PersistentName: TopologyReference] = [:]) {
        self.entries = entries
    }

    public func validate(against model: BRepModel) throws {
        for (name, reference) in entries {
            try name.validate()
            switch reference {
            case let .body(bodyID):
                guard model.bodies[bodyID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Persistent name references a missing body.")
                }
            case let .face(faceID):
                guard model.faces[faceID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Persistent name references a missing face.")
                }
            case let .edge(edgeID):
                guard model.edges[edgeID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Persistent name references a missing edge.")
                }
            case let .vertex(vertexID):
                guard model.vertices[vertexID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Persistent name references a missing vertex.")
                }
            }
        }
    }

    public func reference(for name: PersistentName) throws -> TopologyReference {
        guard let reference = entries[name] else {
            throw FeatureEvaluationError.missingInput("Persistent name could not be resolved.")
        }
        return reference
    }
}

public enum TopologyReference: Hashable, Codable, Sendable {
    case body(BodyID)
    case face(FaceID)
    case edge(EdgeID)
    case vertex(VertexID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case bodyID
        case faceID
        case edgeID
        case vertexID
    }

    private enum Kind: String, Codable {
        case body
        case face
        case edge
        case vertex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .body:
            try container.validateOnlyExpectedKeys([.kind, .bodyID], in: decoder)
            self = .body(try container.decode(BodyID.self, forKey: .bodyID))
        case .face:
            try container.validateOnlyExpectedKeys([.kind, .faceID], in: decoder)
            self = .face(try container.decode(FaceID.self, forKey: .faceID))
        case .edge:
            try container.validateOnlyExpectedKeys([.kind, .edgeID], in: decoder)
            self = .edge(try container.decode(EdgeID.self, forKey: .edgeID))
        case .vertex:
            try container.validateOnlyExpectedKeys([.kind, .vertexID], in: decoder)
            self = .vertex(try container.decode(VertexID.self, forKey: .vertexID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .body(bodyID):
            try container.encode(Kind.body, forKey: .kind)
            try container.encode(bodyID, forKey: .bodyID)
        case let .face(faceID):
            try container.encode(Kind.face, forKey: .kind)
            try container.encode(faceID, forKey: .faceID)
        case let .edge(edgeID):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(edgeID, forKey: .edgeID)
        case let .vertex(vertexID):
            try container.encode(Kind.vertex, forKey: .kind)
            try container.encode(vertexID, forKey: .vertexID)
        }
    }
}
