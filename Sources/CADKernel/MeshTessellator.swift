import CADCore
import CADIR

public struct MeshTessellator: Tessellating {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func tessellate(model: BRepModel, options: TessellationOptions = .standard) throws -> [BodyID: Mesh] {
        do {
            try tolerance.validate()
            try options.validate()
        } catch {
            throw TessellationError.invalidTolerance
        }
        try model.validate(tolerance: tolerance)

        var meshes: [BodyID: Mesh] = [:]
        for (bodyID, body) in model.bodies.sorted(by: { $0.key.description < $1.key.description }) {
            var positions: [Point3D] = []
            var normals: [Vector3D] = []
            var indices: [UInt32] = []

            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                for faceID in shell.faceIDs {
                    try append(
                        faceID: faceID,
                        shellOrientation: shell.orientation,
                        model: model,
                        positions: &positions,
                        normals: &normals,
                        indices: &indices
                    )
                }
            }

            let mesh = Mesh(positions: positions, normals: normals, indices: indices, material: body.material)
            try mesh.validate(tolerance: tolerance)
            meshes[bodyID] = mesh
        }
        return meshes
    }

    private func append(
        faceID: FaceID,
        shellOrientation: Orientation,
        model: BRepModel,
        positions: inout [Point3D],
        normals: inout [Vector3D],
        indices: inout [UInt32]
    ) throws {
        guard let face = model.faces[faceID] else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let outerLoopIDs = face.loops.filter { loopID in
            model.loops[loopID]?.role == .outer
        }
        guard outerLoopIDs.count == 1,
              outerLoopIDs.count == face.loops.count,
              let firstLoopID = outerLoopIDs.first else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let points = try model.orderedPoints(for: firstLoopID)
        guard points.count >= 3 else {
            throw TessellationError.degenerateFace(faceID)
        }
        guard UInt64(positions.count) + UInt64(points.count) <= UInt64(UInt32.max) else {
            throw TessellationError.unsupportedFace(faceID)
        }
        let geometricNormal = try faceNormal(points: points, faceID: faceID)
        let surfaceNormal = try expectedNormal(for: face, shellOrientation: shellOrientation, model: model)
        let shouldReverse = geometricNormal.dot(surfaceNormal) < 0.0
        let normal = surfaceNormal
        let baseIndex = UInt32(positions.count)
        positions.append(contentsOf: points)
        normals.append(contentsOf: Array(repeating: normal, count: points.count))

        for index in 1..<(points.count - 1) {
            indices.append(baseIndex)
            if shouldReverse {
                indices.append(baseIndex + UInt32(index + 1))
                indices.append(baseIndex + UInt32(index))
            } else {
                indices.append(baseIndex + UInt32(index))
                indices.append(baseIndex + UInt32(index + 1))
            }
        }
    }

    private func faceNormal(points: [Point3D], faceID: FaceID) throws -> Vector3D {
        let origin = points[0]
        let areaTolerance = tolerance.distance * tolerance.distance
        for index in 1..<(points.count - 1) {
            let first = points[index] - origin
            let second = points[index + 1] - origin
            let cross = first.cross(second)
            try cross.validate()
            let length = cross.length
            guard length.isFinite else {
                throw GeometryError.invalidVectorLength(length)
            }
            if length > areaTolerance {
                return cross / length
            }
        }
        throw TessellationError.degenerateFace(faceID)
    }

    private func expectedNormal(for face: Face, shellOrientation: Orientation, model: BRepModel) throws -> Vector3D {
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingSurface(face.surfaceID)
        }
        let normal: Vector3D
        switch surface {
        case let .plane(plane):
            normal = try plane.normal.normalized(tolerance: tolerance.distance)
        }
        switch (shellOrientation, face.orientation) {
        case (.forward, .forward), (.reversed, .reversed):
            return normal
        case (.forward, .reversed), (.reversed, .forward):
            return -normal
        }
    }
}
