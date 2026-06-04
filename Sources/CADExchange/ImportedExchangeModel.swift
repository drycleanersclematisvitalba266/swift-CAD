import CADCore
import CADIR

public struct ImportedExchangeModel: Sendable {
    public var format: ExchangeFileFormat
    public var document: CADDocument?
    public var meshes: [BodyID: Mesh]
    public var units: UnitSystem

    public init(
        format: ExchangeFileFormat,
        document: CADDocument? = nil,
        meshes: [BodyID: Mesh] = [:],
        units: UnitSystem = .meters
    ) {
        self.format = format
        self.document = document
        self.meshes = meshes
        self.units = units
    }
}
