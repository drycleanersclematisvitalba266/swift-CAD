import CADCore

public struct CADDocument: Codable, Sendable {
    public var id: DocumentID
    public var schemaVersion: SchemaVersion
    public var units: UnitSystem
    public var parameters: ParameterTable
    public var designGraph: DesignGraph
    public var metadata: DocumentMetadata

    public init(
        id: DocumentID = DocumentID(),
        schemaVersion: SchemaVersion = .current,
        units: UnitSystem,
        parameters: ParameterTable = ParameterTable(),
        designGraph: DesignGraph = DesignGraph(),
        metadata: DocumentMetadata = DocumentMetadata()
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.units = units
        self.parameters = parameters
        self.designGraph = designGraph
        self.metadata = metadata
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try schemaVersion.validate()
        try units.validate()
        try metadata.validate()
        try parameters.validate()
        try designGraph.validate(tolerance: tolerance)
        try designGraph.validateExpressions(using: parameters)
    }
}
