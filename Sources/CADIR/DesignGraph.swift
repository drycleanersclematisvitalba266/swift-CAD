import CADCore

public struct DesignGraph: Codable, Sendable {
    public var nodes: [FeatureID: FeatureNode]
    public var order: [FeatureID]
    public var dependencies: [DependencyEdge]
    public var revision: DocumentRevision

    public init(
        nodes: [FeatureID: FeatureNode] = [:],
        order: [FeatureID] = [],
        dependencies: [DependencyEdge] = [],
        revision: DocumentRevision = DocumentRevision()
    ) {
        self.nodes = nodes
        self.order = order
        self.dependencies = dependencies
        self.revision = revision
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try revision.validate()
        let orderSet = Set(order)
        guard orderSet.count == order.count else {
            throw FeatureEvaluationError.invalidGraph("Feature order contains duplicate IDs.")
        }
        guard Set(dependencies).count == dependencies.count else {
            throw FeatureEvaluationError.invalidGraph("Dependency edges contain duplicates.")
        }
        let nodeIDs = Set(nodes.keys)
        guard orderSet == nodeIDs else {
            throw FeatureEvaluationError.invalidGraph("Feature order must contain every node exactly once.")
        }
        for (featureID, node) in nodes {
            guard node.id == featureID else {
                throw FeatureEvaluationError.invalidGraph("Feature node key does not match its ID.")
            }
            try validateOperationContract(for: node, tolerance: tolerance)
            for input in node.inputs {
                guard nodes[input.featureID] != nil else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references a missing node.")
                }
            }
        }
        for dependency in dependencies {
            guard nodes[dependency.source] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency source is missing.")
            }
            guard nodes[dependency.target] != nil else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
        }
        try validateAcyclicDependencies()
        try validateOrderRespectsDependencies()
        try validateInputsAreRepresentedByDependencies()
        try validateDependenciesAreRepresentedByInputs()
        try validateActiveFeaturesDoNotDependOnSuppressedSources()
    }

    public func validateExpressions(using parameters: ParameterTable) throws {
        for featureID in order {
            guard let node = nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            switch node.operation {
            case let .sketch(sketch):
                try sketch.validateExpressions(using: parameters)
            case let .extrude(extrude):
                let distance = try parameters.resolvedValue(for: extrude.distance)
                guard distance.kind == .length else {
                    throw UnitError.expectedQuantity(
                        operation: "extrude.distance",
                        expected: .length,
                        actual: distance.kind
                    )
                }
                guard distance.value > 0.0 else {
                    throw FeatureEvaluationError.invalidDistance(distance.value)
                }
            }
        }
    }

    private func validateOperationContract(for node: FeatureNode, tolerance: ModelingTolerance) throws {
        let inputRoles = node.inputs.map(\.role)
        guard Set(inputRoles).count == inputRoles.count else {
            throw FeatureEvaluationError.invalidGraph("Feature inputs contain duplicate roles.")
        }
        let outputRoles = node.outputs.map(\.role)
        guard Set(outputRoles).count == outputRoles.count else {
            throw FeatureEvaluationError.invalidGraph("Feature outputs contain duplicate roles.")
        }
        for output in node.outputs {
            try output.persistentName?.validate()
        }

        switch node.operation {
        case let .sketch(sketch):
            guard node.inputs.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Sketch features must not declare inputs.")
            }
            guard outputRoles == [.profile] else {
                throw FeatureEvaluationError.invalidGraph("Sketch features must declare one profile output.")
            }
            try sketch.validate(tolerance: tolerance)
        case let .extrude(extrude):
            try extrude.profile.validate()
            try extrude.distance.validateLiteralQuantities()
            guard node.inputs == [FeatureInput(featureID: extrude.profile.featureID, role: .profile)] else {
                throw FeatureEvaluationError.invalidGraph("Extrude features must consume the referenced profile input.")
            }
            guard let source = nodes[extrude.profile.featureID],
                  source.outputs.contains(where: { $0.role == .profile }) else {
                throw FeatureEvaluationError.invalidGraph("Extrude profile source must declare a profile output.")
            }
            guard outputRoles == [.body] else {
                throw FeatureEvaluationError.invalidGraph("Extrude features must declare one body output.")
            }
            if case let .vector(vector) = extrude.direction {
                try vector.validate()
            }
        }
    }

    private func validateAcyclicDependencies() throws {
        var adjacency: [FeatureID: [FeatureID]] = [:]
        for dependency in dependencies {
            adjacency[dependency.source, default: []].append(dependency.target)
        }
        var states: [FeatureID: VisitState] = [:]
        var stack: [FeatureID] = []
        for featureID in nodes.keys.sorted(by: { $0.description < $1.description }) {
            try visit(featureID, adjacency: adjacency, states: &states, stack: &stack)
        }
    }

    private func visit(
        _ featureID: FeatureID,
        adjacency: [FeatureID: [FeatureID]],
        states: inout [FeatureID: VisitState],
        stack: inout [FeatureID]
    ) throws {
        if states[featureID] == .visited {
            return
        }
        if states[featureID] == .visiting {
            let cycleStart = stack.firstIndex(of: featureID) ?? stack.startIndex
            let cycle = (Array(stack[cycleStart...]) + [featureID])
                .map(\.description)
                .joined(separator: " -> ")
            throw FeatureEvaluationError.invalidGraph("Dependency cycle detected: \(cycle).")
        }

        states[featureID] = .visiting
        stack.append(featureID)
        for targetID in adjacency[featureID, default: []].sorted(by: { $0.description < $1.description }) {
            try visit(targetID, adjacency: adjacency, states: &states, stack: &stack)
        }
        stack.removeLast()
        states[featureID] = .visited
    }

    private func validateOrderRespectsDependencies() throws {
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { index, featureID in
            (featureID, index)
        })
        for dependency in dependencies {
            guard let sourceIndex = positions[dependency.source],
                  let targetIndex = positions[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency references an unordered feature.")
            }
            guard sourceIndex < targetIndex else {
                throw FeatureEvaluationError.invalidGraph("Feature order violates dependency direction.")
            }
        }
        for (featureID, node) in nodes {
            guard let targetIndex = positions[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature node is unordered.")
            }
            for input in node.inputs {
                guard let sourceIndex = positions[input.featureID] else {
                    throw FeatureEvaluationError.invalidGraph("Feature input references an unordered feature.")
                }
                guard sourceIndex < targetIndex else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must appear before the consuming feature.")
                }
            }
        }
    }

    private func validateInputsAreRepresentedByDependencies() throws {
        let dependencySet = Set(dependencies)
        for (featureID, node) in nodes {
            for input in node.inputs {
                let requiredDependency = DependencyEdge(source: input.featureID, target: featureID)
                guard dependencySet.contains(requiredDependency) else {
                    throw FeatureEvaluationError.invalidGraph("Feature input must be represented by a dependency edge.")
                }
            }
        }
    }

    private func validateDependenciesAreRepresentedByInputs() throws {
        for dependency in dependencies {
            guard let target = nodes[dependency.target] else {
                throw FeatureEvaluationError.invalidGraph("Dependency target is missing.")
            }
            guard target.inputs.contains(where: { $0.featureID == dependency.source }) else {
                throw FeatureEvaluationError.invalidGraph("Dependency edge must be represented by a feature input.")
            }
        }
    }

    private func validateActiveFeaturesDoNotDependOnSuppressedSources() throws {
        for (featureID, node) in nodes where !node.isSuppressed {
            for input in node.inputs {
                guard nodes[input.featureID]?.isSuppressed != true else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Active feature input references a suppressed feature."
                    )
                }
            }
            for dependency in dependencies where dependency.target == featureID {
                guard nodes[dependency.source]?.isSuppressed != true else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Active feature dependency references a suppressed feature."
                    )
                }
            }
        }
    }
}

private enum VisitState {
    case visiting
    case visited
}

public struct DependencyEdge: Codable, Sendable, Hashable {
    public var source: FeatureID
    public var target: FeatureID

    public init(source: FeatureID, target: FeatureID) {
        self.source = source
        self.target = target
    }
}
