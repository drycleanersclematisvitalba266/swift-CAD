import Testing
import Foundation
import CADCore
import CADIR
@testable import CADKernel

@Suite("CADKernel")
struct CADKernelTests {
    @Test(.timeLimit(.minutes(1)))
    func parameterResolverResolvesNestedReferences() throws {
        let widthID = ParameterID()
        let heightID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "width",
                expression: .constant(.length(40.0, unit: .millimeter)),
                kind: .length
            ),
            heightID: Parameter(
                id: heightID,
                name: "height",
                expression: .divide(.reference(widthID), .constant(.scalar(2.0))),
                kind: .length
            )
        ])

        let resolved = try ParameterResolver().resolve(table)
        #expect(abs(try resolved.value(for: heightID).value - 0.02) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidUnitAddition() {
        let widthID = ParameterID()
        let table = ParameterTable(parameters: [
            widthID: Parameter(
                id: widthID,
                name: "bad",
                expression: .add(
                    .constant(.length(1.0, unit: .meter)),
                    .constant(.angle(90.0, unit: .degree))
                ),
                kind: .length
            )
        ])

        #expect(throws: UnitError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsParameterTableKeyMismatch() {
        let tableKey = ParameterID()
        let embeddedID = ParameterID()
        let table = ParameterTable(parameters: [
            tableKey: Parameter(
                id: embeddedID,
                name: "width",
                expression: .constant(.length(1.0, unit: .meter)),
                kind: .length
            )
        ])

        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().resolve(table)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverEvaluatesBoundVariables() throws {
        let value = try ParameterResolver().evaluate(
            .variable("offset", .length),
            parameters: ResolvedParameterTable(),
            variables: ["offset": .length(5.0, unit: .millimeter)]
        )

        #expect(value.kind == .length)
        #expect(abs(value.value - 0.005) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func parameterResolverRejectsInvalidVariableNames() {
        #expect(throws: ParameterError.self) {
            _ = try ParameterResolver().evaluate(
                .variable("bad name", .length),
                parameters: ResolvedParameterTable(),
                variables: ["bad name": .length(5.0, unit: .millimeter)]
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rectangleExtrudeCreatesClosedBoxBRepAndDeterministicMesh() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 6)
        #expect(evaluated.brep.edges.count == 12)
        #expect(evaluated.brep.vertices.count == 8)
        try evaluated.brep.validate()
        #expect(evaluated.caches.brep?.parameterRevision == document.parameters.revision)
        #expect(evaluated.generatedNames.values.filter(\.isEdge).count == 12)

        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.indices.count == 36)
        #expect(mesh.positions.count == 24)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)

        let evaluatedAgain = try DocumentEvaluator().evaluate(document)
        #expect(evaluatedAgain.meshes.values.first?.indices == mesh.indices)
    }

    @Test(.timeLimit(.minutes(1)))
    func obliqueVectorExtrudeKeepsCapFacesParallelToSketchPlane() throws {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 0.25, y: 0.5, z: 1.0))
        )
        let evaluated = try DocumentEvaluator().evaluate(document)
        let extrudeFeatureID = try #require(document.designGraph.order.last)
        let startFaceID = try #require(generatedFaceID(
            .startFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let endFaceID = try #require(generatedFaceID(
            .endFace,
            featureID: extrudeFeatureID,
            in: evaluated
        ))
        let startNormal = try planeNormal(for: startFaceID, in: evaluated.brep)
        let endNormal = try planeNormal(for: endFaceID, in: evaluated.brep)

        try evaluated.brep.validate()
        #expect(startNormal.z < -0.9)
        #expect(endNormal.z > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorExtrudeRejectsDirectionParallelToSketchPlane() {
        let document = makeRectangleExtrudeDocument(
            direction: .vector(Vector3D(x: 1.0, y: 1.0, z: 0.0))
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clockwiseProfileExtrudeNormalizesOutwardNormalsAndBalancedEdgeUses() throws {
        let document = makeRectangleExtrudeDocument(clockwiseProfile: true)
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.brep.validate()
        try expectBalancedEdgeOrientations(in: evaluated.brep)
        let mesh = try #require(evaluated.meshes.values.first)
        #expect(mesh.normals[0].z < -0.9)
        let firstNormal = try firstTriangleNormal(in: mesh)
        #expect(firstNormal.dot(mesh.normals[0]) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorAppliesShellAndFaceOrientationToNormals() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        let originalMesh = try #require(evaluated.meshes[bodyID])
        let originalNormal = try #require(originalMesh.normals.first)

        var shellReversedModel = evaluated.brep
        let shellID = try #require(shellReversedModel.shells.keys.first)
        shellReversedModel.shells[shellID]?.orientation = .reversed
        let shellReversedMesh = try #require(MeshTessellator().tessellate(model: shellReversedModel)[bodyID])
        let shellReversedNormal = try #require(shellReversedMesh.normals.first)
        let shellReversedTriangleNormal = try firstTriangleNormal(in: shellReversedMesh)

        var faceReversedModel = evaluated.brep
        let faceID = try #require(faceReversedModel.shells[shellID]?.faceIDs.first)
        faceReversedModel.faces[faceID]?.orientation = .reversed
        let faceReversedMesh = try #require(MeshTessellator().tessellate(model: faceReversedModel)[bodyID])
        let faceReversedNormal = try #require(faceReversedMesh.normals.first)
        let faceReversedTriangleNormal = try firstTriangleNormal(in: faceReversedMesh)

        #expect(shellReversedNormal.dot(originalNormal) < -0.9)
        #expect(shellReversedTriangleNormal.dot(shellReversedNormal) > 0.9)
        #expect(faceReversedNormal.dot(originalNormal) < -0.9)
        #expect(faceReversedTriangleNormal.dot(faceReversedNormal) > 0.9)
    }

    @Test(.timeLimit(.minutes(1)))
    func concaveProfileExtrudeThrowsUnsupportedProfile() {
        let document = makeConcaveExtrudeDocument()

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func profileExtractionRejectsUnsupportedEntitiesInsteadOfIgnoringThem() throws {
        var document = makeRectangleExtrudeDocument()
        let sketchFeatureID = try #require(document.designGraph.order.first)
        var sketchFeature = try #require(document.designGraph.nodes[sketchFeatureID])
        guard case var .sketch(sketch) = sketchFeature.operation else {
            Issue.record("Expected first feature to be a sketch.")
            return
        }
        let circleID = SketchEntityID()
        sketch.entities[circleID] = .circle(SketchCircle(
            center: SketchPoint(
                x: .constant(.length(0.0, unit: .millimeter)),
                y: .constant(.length(0.0, unit: .millimeter))
            ),
            radius: .constant(.length(1.0, unit: .millimeter))
        ))
        sketchFeature.operation = .sketch(sketch)
        document.designGraph.nodes[sketchFeatureID] = sketchFeature

        #expect(throws: SketchError.self) {
            _ = try DocumentEvaluator().evaluate(document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsMissingCurveReference() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        model.geometry.curves.removeValue(forKey: edge.curveID)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedCachesValidateFreshnessAgainstSourceDocument() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        try evaluated.caches.validateFreshness(for: document)
        try evaluated.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsEmptyCachesForBodyProducingDocument() throws {
        let document = makeRectangleExtrudeDocument()

        #expect(throws: CacheValidationError.self) {
            try DocumentCaches().validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelMeshesThatDoNotMatchBRep() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.meshes.keys.first)
        evaluated.meshes[bodyID]?.positions[0].x += 0.25

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsTopLevelBRepThatDoesNotMatchCache() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(evaluated.brep.bodies.keys.first)
        evaluated.brep.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsPersistentNameCacheMismatch() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        evaluated.caches.brep?.persistentNames = PersistentNameMap()

        #expect(throws: CacheValidationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepCacheContentNotEqualToSourceEvaluationEvenWhenMeshesMatch() throws {
        let document = makeRectangleExtrudeDocument()
        var staleCaches = try DocumentEvaluator().evaluate(document).caches
        let bodyID = try #require(staleCaches.brep?.model.bodies.keys.first)
        staleCaches.brep?.model.bodies[bodyID]?.name = "stale-body"

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRejectsInvalidGeneratedNames() throws {
        var invalidNameEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let bodyID = try #require(invalidNameEvaluated.brep.bodies.keys.first)
        invalidNameEvaluated.generatedNames[PersistentName(components: [])] = .body(bodyID)
        invalidNameEvaluated.caches.brep?.persistentNames = PersistentNameMap(invalidNameEvaluated.generatedNames)

        var danglingReferenceEvaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let extrudeFeatureID = try #require(danglingReferenceEvaluated.document.designGraph.order.last)
        let danglingName = PersistentName(components: [
            .feature(extrudeFeatureID),
            .generated(GeneratedSubshapeRole.body.rawValue)
        ])
        danglingReferenceEvaluated.generatedNames[danglingName] = .body(BodyID())
        danglingReferenceEvaluated.caches.brep?.persistentNames = PersistentNameMap(
            danglingReferenceEvaluated.generatedNames
        )

        #expect(throws: FeatureEvaluationError.self) {
            try invalidNameEvaluated.validate()
        }
        #expect(throws: FeatureEvaluationError.self) {
            try danglingReferenceEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluatedDocumentValidationRequiresGeneratedNamesToCoverTopology() throws {
        var evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let edgeName = try #require(evaluated.generatedNames.first { _, reference in
            reference.isEdge
        }?.key)
        evaluated.generatedNames.removeValue(forKey: edgeName)
        evaluated.caches.brep?.persistentNames = PersistentNameMap(evaluated.generatedNames)

        #expect(throws: FeatureEvaluationError.self) {
            try evaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsFailedAndBlockedFeatures() throws {
        let sketchID = FeatureID()
        let extrudeID = FeatureID()
        let lineID = SketchEntityID()
        let openSketch = Sketch(
            plane: .xy,
            entities: [
                lineID: .line(SketchLine(
                    start: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    end: SketchPoint(
                        x: .constant(.length(1.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    )
                ))
            ]
        )
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    sketchID: FeatureNode(
                        id: sketchID,
                        operation: .sketch(openSketch),
                        outputs: [FeatureOutput(role: .profile)]
                    ),
                    extrudeID: FeatureNode(
                        id: extrudeID,
                        operation: .extrude(ExtrudeFeature(
                            profile: ProfileReference(featureID: sketchID),
                            distance: .constant(.length(1.0, unit: .meter))
                        )),
                        inputs: [FeatureInput(featureID: sketchID, role: .profile)],
                        outputs: [FeatureOutput(role: .body)]
                    )
                ],
                order: [sketchID, extrudeID],
                dependencies: [DependencyEdge(source: sketchID, target: extrudeID)]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        guard case let .failed(failure) = report.featureStates[sketchID] else {
            Issue.record("Sketch feature should be marked as failed.")
            return
        }
        #expect(failure.featureID == sketchID)
        #expect(failure.invalidatedFeatureIDs == [extrudeID])
        #expect(report.featureStates[extrudeID] == .blocked(upstreamFeatureID: sketchID))
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportRecordsDocumentLevelFailureAfterFeatureEvaluation() throws {
        let report = DocumentEvaluator(tessellator: EmptyTessellator()).evaluateReport(makeRectangleExtrudeDocument())

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates.values.allSatisfy { $0 == .evaluated })
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func evaluationReportReturnsFailureForDuplicateFeatureOrder() throws {
        let featureID = FeatureID()
        let document = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    featureID: FeatureNode(
                        id: featureID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)]
                    )
                ],
                order: [featureID, featureID]
            )
        )

        let report = DocumentEvaluator().evaluateReport(document)

        #expect(report.evaluatedDocument == nil)
        #expect(report.isComplete == false)
        #expect(report.featureStates[featureID] == .unevaluated)
        #expect(report.failure != nil)
        try report.failure?.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsStaleBRepAndMeshMetadata() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)

        var staleBRepCaches = evaluated.caches
        staleBRepCaches.brep?.parameterRevision = document.parameters.revision.advanced()

        var staleMeshCaches = evaluated.caches
        let bodyID = try #require(staleMeshCaches.meshes.keys.first)
        staleMeshCaches.meshes[bodyID]?.tessellationOptions = TessellationOptions(
            linearTolerance: 1.0e-3,
            angularTolerance: 1.0e-3
        )

        #expect(throws: CacheValidationError.self) {
            try staleBRepCaches.validateFreshness(for: document)
        }
        #expect(throws: CacheValidationError.self) {
            try staleMeshCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsInvalidSourceDocumentAndKernelVersion() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var invalidDocument = document
        invalidDocument.schemaVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        let invalidKernelVersion = SchemaVersion(major: 1, minor: 0, patch: -1)
        var invalidKernelCaches = evaluated.caches
        invalidKernelCaches.brep?.kernelVersion = invalidKernelVersion
        for bodyID in invalidKernelCaches.meshes.keys {
            invalidKernelCaches.meshes[bodyID]?.kernelVersion = invalidKernelVersion
        }

        #expect(throws: SchemaError.self) {
            try evaluated.caches.validateFreshness(for: invalidDocument)
        }
        #expect(throws: SchemaError.self) {
            try invalidKernelCaches.validateFreshness(
                for: document,
                kernelVersion: invalidKernelVersion
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshContentThatDoesNotMatchBRep() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        var staleMeshCache = try #require(staleCaches.meshes[bodyID])
        for index in staleMeshCache.mesh.positions.indices {
            staleMeshCache.mesh.positions[index].x += 0.25
        }
        staleCaches.meshes[bodyID] = staleMeshCache

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsBRepContentFromDifferentSourceEvenWhenMetadataMatches() throws {
        let document = makeRectangleExtrudeDocument(width: 40.0)
        let otherDocument = makeRectangleExtrudeDocument(width: 80.0)
        var staleCaches = try DocumentEvaluator().evaluate(otherDocument).caches
        let sourceFingerprint = try document.sourceFingerprint()
        staleCaches.brep?.designRevision = document.designGraph.revision
        staleCaches.brep?.parameterRevision = document.parameters.revision
        staleCaches.brep?.sourceFingerprint = sourceFingerprint
        for bodyID in staleCaches.meshes.keys {
            staleCaches.meshes[bodyID]?.designRevision = document.designGraph.revision
            staleCaches.meshes[bodyID]?.parameterRevision = document.parameters.revision
            staleCaches.meshes[bodyID]?.sourceFingerprint = sourceFingerprint
        }

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsSourceGraphMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let extrudeFeatureID = try #require(mutatedDocument.designGraph.order.last)
        mutatedDocument.designGraph.nodes[extrudeFeatureID]?.isSuppressed = true
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsParameterMutationWithoutRevisionAdvance() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var mutatedDocument = document
        let widthID = try #require(mutatedDocument.parameters.parameters.values.first { $0.name == "width" }?.id)
        mutatedDocument.parameters.parameters[widthID]?.expression = .constant(.length(80.0, unit: .millimeter))
        try mutatedDocument.validate()

        #expect(throws: CacheValidationError.self) {
            try evaluated.caches.validateFreshness(for: mutatedDocument)
        }

        var staleEvaluated = evaluated
        staleEvaluated.document = mutatedDocument
        #expect(throws: CacheValidationError.self) {
            try staleEvaluated.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cacheFreshnessRejectsMeshCacheTableKeyMismatch() throws {
        let document = makeRectangleExtrudeDocument()
        let evaluated = try DocumentEvaluator().evaluate(document)
        var staleCaches = evaluated.caches
        let bodyID = try #require(staleCaches.meshes.keys.first)
        staleCaches.meshes[bodyID]?.bodyID = BodyID()

        #expect(throws: CacheValidationError.self) {
            try staleCaches.validateFreshness(for: document)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sourceFingerprintIsIndependentOfDictionaryInsertionOrder() throws {
        var document = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: false)
        var reorderedDocument = makeDocumentWithManyIndependentParameters(reverseInsertionOrder: true)
        document.id = fixedDocumentID()
        reorderedDocument.id = document.id

        #expect(try document.sourceFingerprint() == reorderedDocument.sourceFingerprint())
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsInvalidModelingTolerance() {
        let evaluator = DocumentEvaluator(tolerance: ModelingTolerance(distance: .nan, angle: 1.0e-9))

        #expect(throws: GeometryError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsEmptyEvaluationResults() {
        let emptyDocument = CADDocument(units: .meters)
        let suppressedSketchID = FeatureID()
        let suppressedDocument = CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [
                    suppressedSketchID: FeatureNode(
                        id: suppressedSketchID,
                        operation: .sketch(Sketch(plane: .xy)),
                        outputs: [FeatureOutput(role: .profile)],
                        isSuppressed: true
                    )
                ],
                order: [suppressedSketchID]
            )
        )

        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(emptyDocument)
        }
        #expect(throws: FeatureEvaluationError.self) {
            _ = try DocumentEvaluator().evaluate(suppressedDocument)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorRejectsIncompleteGeneratedPersistentNames() {
        let evaluator = DocumentEvaluator(featureEvaluator: IncompleteGeneratedNameFeatureEvaluator())

        #expect(throws: FeatureEvaluationError.self) {
            _ = try evaluator.evaluate(makeRectangleExtrudeDocument())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToDefaultKernelStages() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-9, angle: 1.0e-9)
        let document = makeRectangleExtrudeDocument(
            width: 1.0e-7,
            height: 1.0e-7,
            depth: 1.0e-7,
            unit: .meter,
            documentUnits: .meters
        )

        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)
        let mesh = try #require(evaluated.meshes.values.first)

        try evaluated.brep.validate(tolerance: tolerance)
        try mesh.validate(tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentEvaluatorPropagatesCustomToleranceToSourceValidation() throws {
        let tolerance = ModelingTolerance(distance: 1.0e-3, angle: 1.0e-3)
        let document = makeRectangleExtrudeDocument(
            width: 4.0,
            height: 2.0,
            depth: 1.0,
            unit: .meter,
            documentUnits: .meters,
            sketchPlane: .plane(Plane3D(
                origin: Point3D(x: 0.0, y: 0.0, z: 0.0),
                normal: Vector3D(x: 0.0, y: 0.0, z: 1.0001)
            ))
        )

        #expect(throws: GeometryError.self) {
            try document.validate()
        }
        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluate(document)

        try evaluated.validate()
        try evaluated.caches.validateFreshness(for: document, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func meshTessellatorRejectsNonFiniteTessellationOptions() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        let options = TessellationOptions(linearTolerance: .infinity, angularTolerance: 1.0e-3)

        #expect(throws: TessellationError.self) {
            _ = try MeshTessellator().tessellate(model: evaluated.brep, options: options)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsEdgeTrimEndpointMismatch() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edgeID = try #require(model.edges.keys.first)
        model.edges[edgeID]?.trim = CurveTrim(startParameter: 0.0, endParameter: 0.5)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsDegenerateEdgeGeometry() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let startPoint = try #require(model.vertices[edge.startVertexID]?.point)
        model.vertices[edge.endVertexID]?.point = startPoint

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsFullPeriodCircleTrimAsSingleEdge() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let circlePoint = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = circlePoint
        model.vertices[edge.endVertexID]?.point = circlePoint
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: Double.pi * 2.0)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepValidationRejectsCircleTrimSpanningMoreThanOnePeriod() throws {
        let evaluated = try DocumentEvaluator().evaluate(makeRectangleExtrudeDocument())
        var model = evaluated.brep
        let edge = try #require(model.edges.values.first)
        let curveID = edge.curveID
        let endParameter = Double.pi * 4.0 + 0.25
        model.geometry.curves[curveID] = .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0))
        model.vertices[edge.startVertexID]?.point = Point3D(x: 1.0, y: 0.0, z: 0.0)
        model.vertices[edge.endVertexID]?.point = Point3D(x: cos(0.25), y: sin(0.25), z: 0.0)
        model.edges[edge.id]?.trim = CurveTrim(startParameter: 0.0, endParameter: endParameter)

        #expect(throws: TopologyError.self) {
            try model.validate()
        }
    }
}

private extension TopologyReference {
    var isEdge: Bool {
        if case .edge = self {
            return true
        }
        return false
    }
}

private struct IncompleteGeneratedNameFeatureEvaluator: FeatureEvaluating {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        var result = try PlanarExtrudeFeatureEvaluator().evaluate(feature: feature, context: context)
        if let name = result.generatedNames.first?.key {
            result.generatedNames.removeValue(forKey: name)
        }
        return result
    }
}

private struct EmptyTessellator: Tessellating {
    func tessellate(model: BRepModel, options: TessellationOptions) throws -> [BodyID: Mesh] {
        [:]
    }
}

private func makeRectangleExtrudeDocument(
    width: Double = 40.0,
    height: Double = 20.0,
    depth: Double = 10.0,
    unit: LengthUnit = .millimeter,
    documentUnits: UnitSystem = .millimeters,
    clockwiseProfile: Bool = false,
    sketchPlane: SketchPlane = .xy,
    direction: ExtrudeDirection = .normal
) -> CADDocument {
    let widthID = ParameterID()
    let heightID = ParameterID()
    let depthID = ParameterID()
    let parameters = ParameterTable(parameters: [
        widthID: Parameter(
            id: widthID,
            name: "width",
            expression: .constant(.length(width, unit: unit)),
            kind: .length
        ),
        heightID: Parameter(
            id: heightID,
            name: "height",
            expression: .constant(.length(height, unit: unit)),
            kind: .length
        ),
        depthID: Parameter(
            id: depthID,
            name: "depth",
            expression: .constant(.length(depth, unit: unit)),
            kind: .length
        )
    ])

    let sketch = rectangleSketch(
        widthID: widthID,
        heightID: heightID,
        plane: sketchPlane,
        clockwise: clockwiseProfile
    )
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: direction
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    let designGraph = DesignGraph(
        nodes: [
            sketchFeatureID: sketchFeature,
            extrudeFeatureID: extrudeFeature
        ],
        order: [sketchFeatureID, extrudeFeatureID],
        dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)],
        revision: DocumentRevision(2)
    )
    return CADDocument(units: documentUnits, parameters: parameters, designGraph: designGraph)
}

private func makeDocumentWithManyIndependentParameters(reverseInsertionOrder: Bool) -> CADDocument {
    let parameterIDs = (0..<32).map { index in
        fixedParameterID(index + 1)
    }
    let pairs = parameterIDs.enumerated().map { index, parameterID in
        return (
            parameterID,
            Parameter(
                id: parameterID,
                name: "p\(index)",
                expression: .constant(.length(Double(index + 1), unit: .millimeter)),
                kind: .length
            )
        )
    }
    let orderedPairs = reverseInsertionOrder ? Array(pairs.reversed()) : pairs
    return CADDocument(
        id: fixedDocumentID(),
        units: .millimeters,
        parameters: ParameterTable(parameters: Dictionary(uniqueKeysWithValues: orderedPairs)),
        designGraph: DesignGraph()
    )
}

private func fixedDocumentID() -> DocumentID {
    DocumentID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
}

private func fixedParameterID(_ index: Int) -> ParameterID {
    ParameterID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, UInt8(index))))
}

private func rectangleSketch(
    widthID: ParameterID,
    heightID: ParameterID,
    plane: SketchPlane = .xy,
    clockwise: Bool = false
) -> Sketch {
    let two = CADExpression.constant(.scalar(2.0))
    let minusOne = CADExpression.constant(.scalar(-1.0))
    let halfWidth = CADExpression.divide(.reference(widthID), two)
    let halfHeight = CADExpression.divide(.reference(heightID), two)
    let negativeHalfWidth = CADExpression.multiply(minusOne, halfWidth)
    let negativeHalfHeight = CADExpression.multiply(minusOne, halfHeight)
    let bottomLeft = SketchPoint(x: negativeHalfWidth, y: negativeHalfHeight)
    let bottomRight = SketchPoint(x: halfWidth, y: negativeHalfHeight)
    let topRight = SketchPoint(x: halfWidth, y: halfHeight)
    let topLeft = SketchPoint(x: negativeHalfWidth, y: halfHeight)
    let bottomID = SketchEntityID()
    let rightID = SketchEntityID()
    let topID = SketchEntityID()
    let leftID = SketchEntityID()

    let entities: [SketchEntityID: SketchEntity]
    let constraints: [SketchConstraint]
    if clockwise {
        entities = [
            leftID: .line(SketchLine(start: bottomLeft, end: topLeft)),
            topID: .line(SketchLine(start: topLeft, end: topRight)),
            rightID: .line(SketchLine(start: topRight, end: bottomRight)),
            bottomID: .line(SketchLine(start: bottomRight, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(leftID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(bottomID)),
            .coincident(.lineEnd(bottomID), .lineStart(leftID))
        ]
    } else {
        entities = [
            bottomID: .line(SketchLine(start: bottomLeft, end: bottomRight)),
            rightID: .line(SketchLine(start: bottomRight, end: topRight)),
            topID: .line(SketchLine(start: topRight, end: topLeft)),
            leftID: .line(SketchLine(start: topLeft, end: bottomLeft))
        ]
        constraints = [
            .coincident(.lineEnd(bottomID), .lineStart(rightID)),
            .coincident(.lineEnd(rightID), .lineStart(topID)),
            .coincident(.lineEnd(topID), .lineStart(leftID)),
            .coincident(.lineEnd(leftID), .lineStart(bottomID))
        ]
    }
    return Sketch(plane: plane, entities: entities, constraints: constraints, dimensions: [])
}

private func firstTriangleNormal(in mesh: Mesh) throws -> Vector3D {
    let first = mesh.positions[Int(mesh.indices[0])]
    let second = mesh.positions[Int(mesh.indices[1])]
    let third = mesh.positions[Int(mesh.indices[2])]
    return try (second - first).cross(third - first).normalized(tolerance: ModelingTolerance.standard.distance)
}

private func generatedFaceID(
    _ role: GeneratedSubshapeRole,
    featureID: FeatureID,
    in evaluated: EvaluatedDocument
) -> FaceID? {
    let name = PersistentName(components: [
        .feature(featureID),
        .generated(role.rawValue)
    ])
    guard case let .face(faceID) = evaluated.generatedNames[name] else {
        return nil
    }
    return faceID
}

private func planeNormal(for faceID: FaceID, in model: BRepModel) throws -> Vector3D {
    let face = try #require(model.faces[faceID])
    let surface = try #require(model.geometry.surfaces[face.surfaceID])
    guard case let .plane(plane) = surface else {
        Issue.record("Expected a planar generated face.")
        return .zero
    }
    return try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
}

private func makeConcaveExtrudeDocument() -> CADDocument {
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let points = [
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(0.0, unit: .meter))),
        SketchPoint(x: .constant(.length(1.0, unit: .meter)), y: .constant(.length(1.0, unit: .meter))),
        SketchPoint(x: .constant(.length(2.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter))),
        SketchPoint(x: .constant(.length(0.0, unit: .meter)), y: .constant(.length(2.0, unit: .meter)))
    ]
    var entities: [SketchEntityID: SketchEntity] = [:]
    for index in points.indices {
        entities[SketchEntityID()] = .line(SketchLine(
            start: points[index],
            end: points[(index + 1) % points.count]
        ))
    }
    let sketch = Sketch(plane: .xy, entities: entities)
    let sketchFeature = FeatureNode(
        id: sketchFeatureID,
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    )
    let extrudeFeature = FeatureNode(
        id: extrudeFeatureID,
        operation: .extrude(
            ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .constant(.length(1.0, unit: .meter))
            )
        ),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    )
    return CADDocument(
        units: .meters,
        designGraph: DesignGraph(
            nodes: [
                sketchFeatureID: sketchFeature,
                extrudeFeatureID: extrudeFeature
            ],
            order: [sketchFeatureID, extrudeFeatureID],
            dependencies: [DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID)]
        )
    )
}

private func expectBalancedEdgeOrientations(in model: BRepModel) throws {
    for edgeID in model.edges.keys {
        var forward = 0
        var reversed = 0
        for loop in model.loops.values {
            for orientedEdge in loop.edges where orientedEdge.edgeID == edgeID {
                switch orientedEdge.orientation {
                case .forward:
                    forward += 1
                case .reversed:
                    reversed += 1
                }
            }
        }
        #expect(forward == 1)
        #expect(reversed == 1)
    }
}
