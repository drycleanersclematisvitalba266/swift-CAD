import CADCore
import CADIR

public struct EvaluationReport: Sendable {
    public var document: CADDocument
    public var evaluatedDocument: EvaluatedDocument?
    public var featureStates: [FeatureID: FeatureEvaluationState]
    public var failure: EvaluationFailure?

    public init(
        document: CADDocument,
        evaluatedDocument: EvaluatedDocument?,
        featureStates: [FeatureID: FeatureEvaluationState],
        failure: EvaluationFailure? = nil
    ) {
        self.document = document
        self.evaluatedDocument = evaluatedDocument
        self.featureStates = featureStates
        self.failure = failure
    }

    public var isComplete: Bool {
        evaluatedDocument != nil && featureStates.values.allSatisfy { state in
            switch state {
            case .evaluated, .suppressed:
                true
            case .unevaluated, .blocked, .failed:
                false
            }
        }
    }
}

public struct EvaluationFailure: Sendable, Hashable {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public func validate() throws {
        guard !message.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Evaluation failure message must not be empty.")
        }
    }
}
