import CADCore

public struct Material: Codable, Sendable, Hashable {
    public var id: MaterialID
    public var name: String
    public var baseColor: ColorRGBA
    public var metallic: Double
    public var roughness: Double
    public var opacity: Double

    public init(
        id: MaterialID = MaterialID(),
        name: String,
        baseColor: ColorRGBA,
        metallic: Double,
        roughness: Double,
        opacity: Double
    ) {
        self.id = id
        self.name = name
        self.baseColor = baseColor
        self.metallic = metallic
        self.roughness = roughness
        self.opacity = opacity
    }

    public func validate() throws {
        try baseColor.validate()
        try validateUnitInterval(metallic, field: "metallic")
        try validateUnitInterval(roughness, field: "roughness")
        try validateUnitInterval(opacity, field: "opacity")
    }
}

public struct ColorRGBA: Codable, Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public func validate() throws {
        try validateUnitInterval(r, field: "baseColor.r")
        try validateUnitInterval(g, field: "baseColor.g")
        try validateUnitInterval(b, field: "baseColor.b")
        try validateUnitInterval(a, field: "baseColor.a")
    }
}

private func validateUnitInterval(_ value: Double, field: String) throws {
    guard value.isFinite, (0.0...1.0).contains(value) else {
        throw MaterialError.valueOutOfRange(field: field, value: value)
    }
}
