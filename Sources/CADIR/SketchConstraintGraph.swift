import CADCore

public struct SketchConstraintGraph: Sendable, Equatable {
    public var nodes: Set<SketchConstraintNode>
    public var equations: [SketchConstraintEquation]

    public init(nodes: Set<SketchConstraintNode>, equations: [SketchConstraintEquation]) {
        self.nodes = nodes
        self.equations = equations
    }

    public func validate() throws {
        guard !nodes.isEmpty || equations.isEmpty else {
            throw SketchError.invalidReference("Sketch constraint graph has equations but no nodes.")
        }
        for equation in equations {
            guard !equation.nodes.isEmpty else {
                throw SketchError.invalidReference("Sketch constraint equation has no nodes.")
            }
            for node in equation.nodes {
                guard nodes.contains(node) else {
                    throw SketchError.invalidReference("Sketch constraint equation references a missing graph node.")
                }
            }
        }
    }
}

public struct SketchConstraintNode: Sendable, Codable, Hashable {
    public var reference: SketchReference
    public var degreeOfFreedom: SketchDegreeOfFreedom

    public init(reference: SketchReference, degreeOfFreedom: SketchDegreeOfFreedom) {
        self.reference = reference
        self.degreeOfFreedom = degreeOfFreedom
    }
}

public enum SketchDegreeOfFreedom: String, Codable, Sendable, Hashable {
    case x
    case y
    case radius
    case angle
}

public struct SketchConstraintEquation: Sendable, Codable, Hashable {
    public var kind: SketchConstraintEquationKind
    public var nodes: [SketchConstraintNode]

    public init(kind: SketchConstraintEquationKind, nodes: [SketchConstraintNode]) {
        self.kind = kind
        self.nodes = nodes
    }
}

public enum SketchConstraintEquationKind: String, Codable, Sendable, Hashable {
    case coincident
    case horizontal
    case vertical
    case parallel
    case perpendicular
    case fixed
    case distance
    case radius
    case diameter
}

public extension Sketch {
    func constraintGraph() throws -> SketchConstraintGraph {
        try validate()
        var nodes = Set<SketchConstraintNode>()
        var equations: [SketchConstraintEquation] = []

        func pointNodes(for reference: SketchReference) -> [SketchConstraintNode] {
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .x),
                SketchConstraintNode(reference: reference, degreeOfFreedom: .y)
            ]
        }

        func lineAngleNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            SketchConstraintNode(reference: .entity(entityID), degreeOfFreedom: .angle)
        }

        func circleRadiusNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            SketchConstraintNode(reference: .circleRadius(entityID), degreeOfFreedom: .radius)
        }

        func append(_ kind: SketchConstraintEquationKind, _ equationNodes: [SketchConstraintNode]) {
            for node in equationNodes {
                nodes.insert(node)
            }
            equations.append(SketchConstraintEquation(kind: kind, nodes: equationNodes))
        }

        for constraint in constraints {
            switch constraint {
            case let .coincident(first, second):
                append(.coincident, pointNodes(for: first) + pointNodes(for: second))
            case let .horizontal(entityID):
                append(.horizontal, [lineAngleNode(for: entityID)])
            case let .vertical(entityID):
                append(.vertical, [lineAngleNode(for: entityID)])
            case let .parallel(first, second):
                append(.parallel, [lineAngleNode(for: first), lineAngleNode(for: second)])
            case let .perpendicular(first, second):
                append(.perpendicular, [lineAngleNode(for: first), lineAngleNode(for: second)])
            case let .fixed(reference):
                append(.fixed, degreesOfFreedom(for: reference))
            }
        }

        for dimension in dimensions {
            switch dimension {
            case let .distance(from, to, _):
                append(.distance, pointNodes(for: from) + pointNodes(for: to))
            case let .radius(entityID, _):
                append(.radius, [circleRadiusNode(for: entityID)])
            case let .diameter(entityID, _):
                append(.diameter, [circleRadiusNode(for: entityID)])
            }
        }

        let graph = SketchConstraintGraph(nodes: nodes, equations: equations)
        try graph.validate()
        return graph
    }

    private func degreesOfFreedom(for reference: SketchReference) -> [SketchConstraintNode] {
        switch reference {
        case .entity, .lineStart, .lineEnd, .circleCenter:
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .x),
                SketchConstraintNode(reference: reference, degreeOfFreedom: .y)
            ]
        case .circleRadius:
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .radius)
            ]
        }
    }
}
