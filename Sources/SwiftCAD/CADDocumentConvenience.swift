import CADCore
import CADIR

public extension CADDocument {
    static func millimeters(
        named name: String? = nil,
        _ build: (inout DocumentBuilder) throws -> Void
    ) throws -> CADDocument {
        try make(units: .millimeters, named: name, build)
    }

    static func make(
        units: UnitSystem,
        named name: String? = nil,
        _ build: (inout DocumentBuilder) throws -> Void
    ) throws -> CADDocument {
        var builder = DocumentBuilder(units: units)
        try build(&builder)
        return try builder.build(name: name)
    }
}
