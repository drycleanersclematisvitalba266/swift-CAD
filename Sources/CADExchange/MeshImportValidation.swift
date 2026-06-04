import CADCore
import CADIR

func validateImportedMesh(_ mesh: Mesh, formatName: String) throws {
    do {
        try mesh.validate()
    } catch let error as ExportError {
        throw ImportError.invalidData("\(formatName) mesh is invalid: \(error).")
    }
}
