import CADCore

func checkedExportUnitValue(
    _ value: Double,
    formatName: String,
    component: String
) throws -> Double {
    guard value.isFinite else {
        throw ExportError.invalidMesh("\(formatName) \(component) is not finite after unit conversion.")
    }
    return value
}
