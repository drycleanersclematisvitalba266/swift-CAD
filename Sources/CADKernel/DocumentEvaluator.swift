import CADCore
import CADIR

public struct DocumentEvaluator: Sendable {
    private let parameterResolver: ParameterResolving
    private let profileExtractor: SketchProfileExtracting
    private let featureEvaluator: FeatureEvaluating
    private let tessellator: Tessellating
    private let tolerance: ModelingTolerance
    private let tessellationOptions: TessellationOptions

    public init(
        parameterResolver: ParameterResolving = ParameterResolver(),
        profileExtractor: SketchProfileExtracting? = nil,
        featureEvaluator: FeatureEvaluating? = nil,
        tessellator: Tessellating? = nil,
        tolerance: ModelingTolerance = .standard,
        tessellationOptions: TessellationOptions = .standard
    ) {
        self.parameterResolver = parameterResolver
        self.profileExtractor = profileExtractor ?? SketchProfileExtractor(
            resolver: parameterResolver,
            tolerance: tolerance
        )
        self.featureEvaluator = featureEvaluator ?? PlanarExtrudeFeatureEvaluator(resolver: parameterResolver)
        self.tessellator = tessellator ?? MeshTessellator(tolerance: tolerance)
        self.tolerance = tolerance
        self.tessellationOptions = tessellationOptions
    }

    public func evaluate(_ document: CADDocument) throws -> EvaluatedDocument {
        let evaluatedDocument = try evaluateWithoutCacheValidation(document)
        try evaluatedDocument.caches.validateFreshness(
            for: document,
            tolerance: tolerance,
            tessellationOptions: tessellationOptions,
            kernelVersion: .current
        )
        return evaluatedDocument
    }

    public func evaluateReport(_ document: CADDocument) -> EvaluationReport {
        var states: [FeatureID: FeatureEvaluationState] = [:]
        for featureID in document.designGraph.order {
            states[featureID] = .unevaluated
        }
        do {
            let evaluatedDocument = try evaluate(document) { featureID, state in
                states[featureID] = state
            }
            return EvaluationReport(
                document: document,
                evaluatedDocument: evaluatedDocument,
                featureStates: states
            )
        } catch {
            let failure = EvaluationFailure(message: String(describing: error))
            return EvaluationReport(
                document: document,
                evaluatedDocument: nil,
                featureStates: states,
                failure: failure
            )
        }
    }

    func evaluateWithoutCacheValidation(_ document: CADDocument) throws -> EvaluatedDocument {
        try evaluate(document, stateRecorder: { _, _ in })
    }

    private func evaluate(
        _ document: CADDocument,
        stateRecorder: (FeatureID, FeatureEvaluationState) -> Void
    ) throws -> EvaluatedDocument {
        try tolerance.validate()
        try tessellationOptions.validate()
        try document.validate(tolerance: tolerance)
        let sourceFingerprint = try document.sourceFingerprint(tolerance: tolerance)
        let parameters = try parameterResolver.resolve(document.parameters)
        var brep = BRepModel()
        var profiles: [FeatureID: [Profile]] = [:]
        var generatedNames: [PersistentName: TopologyReference] = [:]

        for featureID in document.designGraph.order {
            guard let feature = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Feature order references missing node.")
            }
            guard !feature.isSuppressed else {
                stateRecorder(featureID, .suppressed)
                continue
            }

            do {
                switch feature.operation {
                case let .sketch(sketch):
                    profiles[feature.id] = try profileExtractor.extractProfiles(
                        from: sketch,
                        sourceFeatureID: feature.id,
                        parameters: parameters
                    )
                case .extrude:
                    let context = EvaluationContext(
                        parameters: parameters,
                        brep: brep,
                        profiles: profiles,
                        tolerance: tolerance
                    )
                    let result = try featureEvaluator.evaluate(feature: feature, context: context)
                    brep = result.brep
                    try mergeGeneratedNames(result.generatedNames, into: &generatedNames)
                }
                stateRecorder(featureID, .evaluated)
            } catch {
                let invalidated: [FeatureID]
                do {
                    invalidated = try document.designGraph.invalidatedFeatureIDs(after: featureID)
                } catch {
                    invalidated = []
                }
                let failure = FeatureFailure(
                    featureID: featureID,
                    message: String(describing: error),
                    invalidatedFeatureIDs: invalidated
                )
                stateRecorder(featureID, .failed(failure))
                for invalidatedFeatureID in invalidated {
                    stateRecorder(invalidatedFeatureID, .blocked(upstreamFeatureID: featureID))
                }
                throw error
            }
        }

        try brep.validate(tolerance: tolerance)
        let meshes = try tessellator.tessellate(model: brep, options: tessellationOptions)
        guard !meshes.isEmpty else {
            throw FeatureEvaluationError.emptyResult("Evaluation produced no body meshes.")
        }
        let brepCache = BRepCache(
            designRevision: document.designGraph.revision,
            parameterRevision: document.parameters.revision,
            sourceFingerprint: sourceFingerprint,
            kernelVersion: .current,
            tolerance: tolerance,
            model: brep,
            persistentNames: PersistentNameMap(generatedNames)
        )
        let meshCaches = Dictionary(
            uniqueKeysWithValues: meshes.map { bodyID, mesh in
                (
                    bodyID,
                    MeshCache(
                        bodyID: bodyID,
                        designRevision: document.designGraph.revision,
                        parameterRevision: document.parameters.revision,
                        sourceFingerprint: sourceFingerprint,
                        kernelVersion: .current,
                        tolerance: tolerance,
                        tessellationOptions: tessellationOptions,
                        mesh: mesh
                    )
                )
            }
        )
        let caches = DocumentCaches(brep: brepCache, meshes: meshCaches)
        let evaluatedDocument = EvaluatedDocument(
            document: document,
            parameters: parameters,
            brep: brep,
            meshes: meshes,
            caches: caches,
            generatedNames: generatedNames
        )
        try evaluatedDocument.validateGeneratedNames()
        return evaluatedDocument
    }

    private func mergeGeneratedNames(
        _ newNames: [PersistentName: TopologyReference],
        into generatedNames: inout [PersistentName: TopologyReference]
    ) throws {
        for (name, reference) in newNames {
            if generatedNames[name] != nil {
                throw FeatureEvaluationError.invalidGraph("Generated persistent name collision.")
            }
            generatedNames[name] = reference
        }
    }
}
