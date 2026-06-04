import CADCore

public extension CADExpression {
    static func length(_ value: Double, _ unit: LengthUnit) -> CADExpression {
        .constant(.length(value, unit: unit))
    }

    static func angle(_ value: Double, _ unit: AngleUnit) -> CADExpression {
        .constant(.angle(value, unit: unit))
    }

    static func scalar(_ value: Double) -> CADExpression {
        .constant(.scalar(value))
    }

    static func parameter(_ id: ParameterID) -> CADExpression {
        .reference(id)
    }
}
