import CADCore
import CADIR

public struct PlanarExtrudeFeatureEvaluator: FeatureEvaluating {
    private let resolver: ParameterResolving

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .extrude(extrude) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarExtrudeFeatureEvaluator only supports extrude.")
        }
        guard extrude.operation == .newBody else {
            throw FeatureEvaluationError.unsupportedOperation("PlanarExtrudeFeatureEvaluator only supports newBody extrude.")
        }
        guard let profiles = context.profiles[extrude.profile.featureID],
              profiles.indices.contains(extrude.profile.profileIndex) else {
            throw FeatureEvaluationError.missingProfile(
                extrude.profile.featureID,
                extrude.profile.profileIndex
            )
        }

        let distance = try resolver.evaluate(extrude.distance, parameters: context.parameters, variables: [:])
        guard distance.kind == .length else {
            throw UnitError.expectedQuantity(operation: "extrude.distance", expected: .length, actual: distance.kind)
        }
        guard distance.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance.value)
        }

        let profile = profiles[extrude.profile.profileIndex]
        return try buildBody(
            from: profile,
            featureID: feature.id,
            direction: extrude.direction,
            distance: distance.value,
            context: context
        )
    }

    private func buildBody(
        from profile: Profile,
        featureID: FeatureID,
        direction: ExtrudeDirection,
        distance: Double,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard profile.vertices.count >= 3 else {
            throw SketchError.openProfile
        }

        let profileNormal = try normal(for: profile.plane, tolerance: context.tolerance)
        let extrusionDirection = try extrusionDirectionVector(
            for: direction,
            plane: profile.plane,
            tolerance: context.tolerance
        )
        let normalComponent = extrusionDirection.dot(profileNormal)
        guard abs(normalComponent) > context.tolerance.angle else {
            throw FeatureEvaluationError.invalidDirection(extrusionDirection)
        }
        let extrusionSign = normalComponent >= 0.0 ? 1.0 : -1.0
        let capNormal = profileNormal * extrusionSign
        let bottomOffset: Vector3D
        let topOffset: Vector3D
        switch direction {
        case .symmetric:
            bottomOffset = extrusionDirection * (-distance / 2.0)
            topOffset = extrusionDirection * (distance / 2.0)
        case .normal, .vector:
            bottomOffset = .zero
            topOffset = extrusionDirection * distance
        }

        var model = context.brep
        var generatedNames: [PersistentName: TopologyReference] = [:]
        var geometry = model.geometry

        let bodyID = BodyID()
        let shellID = ShellID()
        let vertexCount = profile.vertices.count

        var bottomVertexIDs: [VertexID] = []
        var topVertexIDs: [VertexID] = []
        for index in 0..<vertexCount {
            let bottomID = VertexID()
            let topID = VertexID()
            bottomVertexIDs.append(bottomID)
            topVertexIDs.append(topID)
            model.vertices[bottomID] = Vertex(id: bottomID, point: profile.vertices[index] + bottomOffset)
            model.vertices[topID] = Vertex(id: topID, point: profile.vertices[index] + topOffset)
            generatedNames[persistentName(featureID, .vertex, index)] = .vertex(bottomID)
            generatedNames[persistentName(featureID, .vertex, index + vertexCount)] = .vertex(topID)
        }

        var bottomEdgeIDs: [EdgeID] = []
        var topEdgeIDs: [EdgeID] = []
        var verticalEdgeIDs: [EdgeID] = []
        for index in 0..<vertexCount {
            let next = (index + 1) % vertexCount
            let bottomEdgeID = try addEdge(
                from: bottomVertexIDs[index],
                to: bottomVertexIDs[next],
                model: &model,
                geometry: &geometry,
                tolerance: context.tolerance
            )
            bottomEdgeIDs.append(bottomEdgeID)
            generatedNames[persistentName(featureID, .edge, index)] = .edge(bottomEdgeID)

            let topEdgeID = try addEdge(
                from: topVertexIDs[index],
                to: topVertexIDs[next],
                model: &model,
                geometry: &geometry,
                tolerance: context.tolerance
            )
            topEdgeIDs.append(topEdgeID)
            generatedNames[persistentName(featureID, .edge, index + vertexCount)] = .edge(topEdgeID)

            let verticalEdgeID = try addEdge(
                from: bottomVertexIDs[index],
                to: topVertexIDs[index],
                model: &model,
                geometry: &geometry,
                tolerance: context.tolerance
            )
            verticalEdgeIDs.append(verticalEdgeID)
            generatedNames[persistentName(featureID, .edge, index + vertexCount * 2)] = .edge(verticalEdgeID)
        }

        var faceIDs: [FaceID] = []
        let bottomOrigin = try point(for: bottomVertexIDs[0], in: model)
        let topOrigin = try point(for: topVertexIDs[0], in: model)
        let bottomFaceID = try addFace(
            role: .startFace,
            featureID: featureID,
            index: nil,
            loopEdges: bottomEdgeIDs.indices.reversed().map { index in
                OrientedEdge(edgeID: bottomEdgeIDs[index], orientation: .reversed)
            },
            planeOrigin: bottomOrigin,
            planeNormal: -capNormal,
            model: &model,
            geometry: &geometry,
            generatedNames: &generatedNames
        )
        faceIDs.append(bottomFaceID)

        let topFaceID = try addFace(
            role: .endFace,
            featureID: featureID,
            index: nil,
            loopEdges: topEdgeIDs.map { OrientedEdge(edgeID: $0, orientation: .forward) },
            planeOrigin: topOrigin,
            planeNormal: capNormal,
            model: &model,
            geometry: &geometry,
            generatedNames: &generatedNames
        )
        faceIDs.append(topFaceID)

        for index in 0..<vertexCount {
            let next = (index + 1) % vertexCount
            let start = try point(for: bottomVertexIDs[index], in: model)
            let end = try point(for: bottomVertexIDs[next], in: model)
            let edgeDirection = try (end - start).normalized(tolerance: context.tolerance.distance)
            let sideNormal = try (edgeDirection.cross(extrusionDirection) * extrusionSign)
                .normalized(tolerance: context.tolerance.distance)
            let faceID = try addFace(
                role: .sideFace,
                featureID: featureID,
                index: index,
                loopEdges: [
                    OrientedEdge(edgeID: bottomEdgeIDs[index], orientation: .forward),
                    OrientedEdge(edgeID: verticalEdgeIDs[next], orientation: .forward),
                    OrientedEdge(edgeID: topEdgeIDs[index], orientation: .reversed),
                    OrientedEdge(edgeID: verticalEdgeIDs[index], orientation: .reversed)
                ],
                planeOrigin: start,
                planeNormal: sideNormal,
                model: &model,
                geometry: &geometry,
                generatedNames: &generatedNames
            )
            faceIDs.append(faceID)
        }

        model.geometry = geometry
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID])
        generatedNames[persistentName(featureID, .body, nil)] = .body(bodyID)
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(brep: model, generatedNames: generatedNames)
    }

    private func addEdge(
        from startID: VertexID,
        to endID: VertexID,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        tolerance: ModelingTolerance
    ) throws -> EdgeID {
        guard let start = model.vertices[startID]?.point,
              let end = model.vertices[endID]?.point else {
            throw TopologyError.missingReference("Missing edge vertex.")
        }
        let delta = end - start
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let curveID = CurveID()
        let edgeID = EdgeID()
        geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startID,
            endVertexID: endID,
            trim: CurveTrim(startParameter: 0.0, endParameter: delta.length)
        )
        return edgeID
    }

    private func addFace(
        role: GeneratedSubshapeRole,
        featureID: FeatureID,
        index: Int?,
        loopEdges: [OrientedEdge],
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        model: inout BRepModel,
        geometry: inout GeometryStore,
        generatedNames: inout [PersistentName: TopologyReference]
    ) throws -> FaceID {
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        geometry.surfaces[surfaceID] = .plane(Plane3D(origin: planeOrigin, normal: planeNormal))
        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: loopEdges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        generatedNames[persistentName(featureID, role, index)] = .face(faceID)
        return faceID
    }

    private func extrusionDirectionVector(
        for direction: ExtrudeDirection,
        plane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        switch direction {
        case .normal, .symmetric:
            return try normal(for: plane, tolerance: tolerance)
        case let .vector(vector):
            do {
                return try vector.normalized(tolerance: tolerance.distance)
            } catch GeometryError.invalidVectorLength {
                throw FeatureEvaluationError.invalidDirection(vector)
            }
        }
    }

    private func normal(for plane: SketchPlane, tolerance: ModelingTolerance) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }

    private func persistentName(_ featureID: FeatureID, _ role: GeneratedSubshapeRole, _ index: Int?) -> PersistentName {
        var components: [NameComponent] = [.feature(featureID), .generated(role.rawValue)]
        if let index {
            components.append(.index(index))
        }
        return PersistentName(components: components)
    }

    private func point(for vertexID: VertexID, in model: BRepModel) throws -> Point3D {
        guard let point = model.vertices[vertexID]?.point else {
            throw TopologyError.missingReference("Missing vertex \(vertexID).")
        }
        return point
    }
}
