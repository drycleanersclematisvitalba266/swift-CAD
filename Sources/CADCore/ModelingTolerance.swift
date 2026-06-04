public struct ModelingTolerance: Codable, Hashable, Sendable {
    public var distance: Double
    public var angle: Double

    public init(distance: Double, angle: Double) {
        self.distance = distance
        self.angle = angle
    }

    public static let standard = ModelingTolerance(distance: 1.0e-6, angle: 1.0e-9)

    public func validate() throws {
        guard distance.isFinite,
              distance > 0.0,
              angle.isFinite,
              angle > 0.0 else {
            throw GeometryError.invalidTolerance(distance: distance, angle: angle)
        }
    }
}
