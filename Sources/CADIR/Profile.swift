import CADCore

public struct ProfileReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID
    public var profileIndex: Int

    public init(featureID: FeatureID, profileIndex: Int = 0) {
        self.featureID = featureID
        self.profileIndex = profileIndex
    }

    public func validate() throws {
        guard profileIndex >= 0 else {
            throw FeatureEvaluationError.invalidGraph("Profile index must not be negative.")
        }
    }
}

public struct Profile: Sendable, Hashable {
    public var sourceFeatureID: FeatureID
    public var plane: SketchPlane
    public var vertices: [Point3D]

    public init(sourceFeatureID: FeatureID, plane: SketchPlane, vertices: [Point3D]) {
        self.sourceFeatureID = sourceFeatureID
        self.plane = plane
        self.vertices = vertices
    }
}
