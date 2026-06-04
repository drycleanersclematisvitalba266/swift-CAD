import CADCore

public struct Sketch: Codable, Sendable {
    public var id: SketchID
    public var plane: SketchPlane
    public var entities: [SketchEntityID: SketchEntity]
    public var constraints: [SketchConstraint]
    public var dimensions: [SketchDimension]

    public init(
        id: SketchID = SketchID(),
        plane: SketchPlane,
        entities: [SketchEntityID: SketchEntity] = [:],
        constraints: [SketchConstraint] = [],
        dimensions: [SketchDimension] = []
    ) {
        self.id = id
        self.plane = plane
        self.entities = entities
        self.constraints = constraints
        self.dimensions = dimensions
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        if case let .plane(plane) = plane {
            try plane.validate(tolerance: tolerance)
        }
        for entity in entities.values {
            try validateLiteralQuantities(in: entity)
        }
        for constraint in constraints {
            try validate(constraint)
        }
        for dimension in dimensions {
            try validate(dimension)
        }
    }

    public func validateExpressions(using parameters: ParameterTable) throws {
        for entity in entities.values {
            try validateExpressions(in: entity, using: parameters)
        }
        for dimension in dimensions {
            try validateExpression(in: dimension, using: parameters)
        }
    }

    private func validateExpressions(in entity: SketchEntity, using parameters: ParameterTable) throws {
        switch entity {
        case let .point(point):
            try resolveLengthExpression(point.x, operation: "sketch.x", using: parameters)
            try resolveLengthExpression(point.y, operation: "sketch.y", using: parameters)
        case let .line(line):
            try resolveLengthExpression(line.start.x, operation: "sketch.line.start.x", using: parameters)
            try resolveLengthExpression(line.start.y, operation: "sketch.line.start.y", using: parameters)
            try resolveLengthExpression(line.end.x, operation: "sketch.line.end.x", using: parameters)
            try resolveLengthExpression(line.end.y, operation: "sketch.line.end.y", using: parameters)
        case let .circle(circle):
            try resolveLengthExpression(circle.center.x, operation: "sketch.circle.center.x", using: parameters)
            try resolveLengthExpression(circle.center.y, operation: "sketch.circle.center.y", using: parameters)
            let radius = try resolveLengthExpression(
                circle.radius,
                operation: "sketch.circle.radius",
                using: parameters
            )
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        }
    }

    private func validateExpression(in dimension: SketchDimension, using parameters: ParameterTable) throws {
        switch dimension {
        case let .distance(_, _, value):
            let distance = try resolveLengthExpression(value, operation: "sketch.dimension.distance", using: parameters)
            guard distance.value >= 0.0 else {
                throw GeometryError.invalidDistance(distance.value)
            }
        case let .radius(_, value):
            let radius = try resolveLengthExpression(value, operation: "sketch.dimension.radius", using: parameters)
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        case let .diameter(_, value):
            let diameter = try resolveLengthExpression(value, operation: "sketch.dimension.diameter", using: parameters)
            guard diameter.value > 0.0 else {
                throw GeometryError.invalidDistance(diameter.value)
            }
        }
    }

    @discardableResult
    private func resolveLengthExpression(
        _ expression: CADExpression,
        operation: String,
        using parameters: ParameterTable
    ) throws -> Quantity {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: quantity.kind)
        }
        return quantity
    }

    private func validateLiteralQuantities(in entity: SketchEntity) throws {
        switch entity {
        case let .point(point):
            try point.x.validateLiteralQuantities()
            try point.y.validateLiteralQuantities()
        case let .line(line):
            try line.start.x.validateLiteralQuantities()
            try line.start.y.validateLiteralQuantities()
            try line.end.x.validateLiteralQuantities()
            try line.end.y.validateLiteralQuantities()
        case let .circle(circle):
            try circle.center.x.validateLiteralQuantities()
            try circle.center.y.validateLiteralQuantities()
            try circle.radius.validateLiteralQuantities()
        }
    }

    private func validate(_ constraint: SketchConstraint) throws {
        switch constraint {
        case let .coincident(first, second):
            try validatePointReference(first)
            try validatePointReference(second)
        case let .horizontal(entityID), let .vertical(entityID):
            try validateLineEntity(entityID)
        case let .parallel(first, second), let .perpendicular(first, second):
            try validateLineEntity(first)
            try validateLineEntity(second)
        case let .fixed(reference):
            try validateReference(reference)
        }
    }

    private func validate(_ dimension: SketchDimension) throws {
        switch dimension {
        case let .distance(from, to, value):
            try validatePointReference(from)
            try validatePointReference(to)
            try value.validateLiteralQuantities()
        case let .radius(entityID, value), let .diameter(entityID, value):
            try validateCircleEntity(entityID)
            try value.validateLiteralQuantities()
        }
    }

    private func validateReference(_ reference: SketchReference) throws {
        switch reference {
        case let .entity(entityID):
            guard entities[entityID] != nil else {
                throw SketchError.invalidReference("Sketch reference points to a missing entity.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID)
        case let .circleCenter(entityID), let .circleRadius(entityID):
            try validateCircleEntity(entityID)
        }
    }

    private func validatePointReference(_ reference: SketchReference) throws {
        switch reference {
        case let .entity(entityID):
            guard let entity = entities[entityID], case .point = entity else {
                throw SketchError.invalidReference("Entity reference must point to a sketch point.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID)
        case let .circleCenter(entityID):
            try validateCircleEntity(entityID)
        case .circleRadius:
            throw SketchError.invalidReference("Circle radius is not a point reference.")
        }
    }

    private func validateLineEntity(_ entityID: SketchEntityID) throws {
        guard let entity = entities[entityID], case .line = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a line entity.")
        }
    }

    private func validateCircleEntity(_ entityID: SketchEntityID) throws {
        guard let entity = entities[entityID], case .circle = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a circle entity.")
        }
    }
}
