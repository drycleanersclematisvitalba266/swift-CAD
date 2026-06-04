import CADCore

public struct GeometryStore: Codable, Equatable, Sendable {
    public var curves: [CurveID: Curve3D]
    public var surfaces: [SurfaceID: Surface3D]

    public init(curves: [CurveID: Curve3D] = [:], surfaces: [SurfaceID: Surface3D] = [:]) {
        self.curves = curves
        self.surfaces = surfaces
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        for curve in curves.values {
            try curve.validate(tolerance: tolerance)
        }
        for surface in surfaces.values {
            try surface.validate(tolerance: tolerance)
        }
    }
}
