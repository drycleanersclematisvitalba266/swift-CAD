import Foundation
import CADCore
import CADIR

public struct USDExporter: Sendable {
    private let conversionToolchain: any USDConversionToolchain

    public init(conversionToolchain: any USDConversionToolchain = SystemUSDConversionToolchain()) {
        self.conversionToolchain = conversionToolchain
    }

    public func write(meshes: [BodyID: Mesh], encoding: USDEncoding, unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        switch encoding {
        case .usd, .usda:
            try writeUSDA(meshes: meshes, unit: unit, to: sink)
        case .usdc:
            try withTemporaryUSDA(meshes: meshes, unit: unit) { url in
                let validator = SignatureValidatingByteSink(sink, encoding: .usdc)
                try conversionToolchain.writeUSDC(fromUSDA: url, to: validator)
                try validator.finish()
            }
        case .usdz:
            try withTemporaryUSDA(meshes: meshes, unit: unit) { url in
                let validator = SignatureValidatingByteSink(sink, encoding: .usdz)
                try conversionToolchain.writeUSDZ(fromUSDA: url, to: validator)
                try validator.finish()
            }
        }
    }

    private func writeUSDA(meshes: [BodyID: Mesh], unit: LengthUnit, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        try sink.writeUTF8("""
        #usda 1.0
        (
            defaultPrim = "SwiftCADScene"
            metersPerUnit = \(unit.metersPerUnit)
            upAxis = "Z"
        )

        def Xform "SwiftCADScene"
        {
        """)
        for (bodyID, mesh) in meshes.sorted(by: { $0.key.description < $1.key.description }) {
            try mesh.validate()
            let name = "Body_\(bodyID.rawValue.uuidString.replacingOccurrences(of: "-", with: "_"))"
            try sink.writeUTF8("""
            
                def Mesh "\(name)"
                {
                    point3f[] points = [
            """)
            for (index, point) in mesh.positions.enumerated() {
                let x = try usdPoint3fNumber(unit.fromInternal(point.x), label: "point.x")
                let y = try usdPoint3fNumber(unit.fromInternal(point.y), label: "point.y")
                let z = try usdPoint3fNumber(unit.fromInternal(point.z), label: "point.z")
                if index > 0 {
                    try sink.writeUTF8(", ")
                }
                try sink.writeUTF8("(\(x), \(y), \(z))")
            }
            try sink.writeUTF8("]\n                int[] faceVertexCounts = [")
            let triangleCount = mesh.indices.count / 3
            for index in 0..<triangleCount {
                if index > 0 {
                    try sink.writeUTF8(", ")
                }
                try sink.writeUTF8("3")
            }
            try sink.writeUTF8("]\n                int[] faceVertexIndices = [")
            for (index, meshIndex) in mesh.indices.enumerated() {
                if index > 0 {
                    try sink.writeUTF8(", ")
                }
                try sink.writeUTF8("\(meshIndex)")
            }
            try sink.writeUTF8("""
            ]
                    uniform token subdivisionScheme = "none"
                }
            """)
        }
        try sink.writeUTF8("\n}")
    }

    private func withTemporaryUSDA<T>(
        meshes: [BodyID: Mesh],
        unit: LengthUnit,
        operation: (URL) throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent("SwiftCAD-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let inputURL = directoryURL.appendingPathComponent("scene.usda")
        do {
            let fileSink = try FileByteSink(url: inputURL)
            try writeUSDA(meshes: meshes, unit: unit, to: fileSink)
            try fileSink.close()
            let result = try operation(inputURL)
            try fileManager.removeItem(at: directoryURL)
            return result
        } catch {
            let primaryError = error
            do {
                try fileManager.removeItem(at: directoryURL)
            } catch {
                throw ExportError.fileWriteFailure(
                    "Failed to remove temporary USD directory after error \(primaryError.localizedDescription): \(error.localizedDescription)"
                )
            }
            throw primaryError
        }
    }
}

private func usdPoint3fNumber(_ value: Double, label: String) throws -> String {
    let value32 = Float32(value)
    guard value32.isFinite else {
        throw ExportError.invalidMesh("USD \(label) is outside Float32 range.")
    }
    return String(format: "%.9g", locale: Locale(identifier: "en_US_POSIX"), Double(value32))
}

private final class SignatureValidatingByteSink: ByteSink {
    private let downstream: any ByteSink
    private let encoding: USDEncoding
    private var prefix: [UInt8] = []
    private var isValidated = false

    init(_ downstream: any ByteSink, encoding: USDEncoding) {
        self.downstream = downstream
        self.encoding = encoding
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard !requiredPrefix.isEmpty else {
            try downstream.write(bytes)
            return
        }
        guard !isValidated else {
            try downstream.write(bytes)
            return
        }

        var consumedCount = 0
        for byte in bytes where prefix.count < requiredPrefix.count {
            prefix.append(byte)
            consumedCount += 1
        }
        guard prefix.count >= requiredPrefix.count else {
            return
        }
        guard prefix == requiredPrefix else {
            throw invalidSignatureError()
        }

        isValidated = true
        try prefix.withUnsafeBytes { prefixBytes in
            try downstream.write(prefixBytes)
        }
        guard consumedCount < bytes.count, let baseAddress = bytes.baseAddress else {
            return
        }
        let remaining = UnsafeRawBufferPointer(
            start: baseAddress.advanced(by: consumedCount),
            count: bytes.count - consumedCount
        )
        try downstream.write(remaining)
    }

    func finish() throws {
        guard requiredPrefix.isEmpty || isValidated else {
            throw invalidSignatureError()
        }
    }

    private func invalidSignatureError() -> ExportError {
        ExportError.externalToolFailure(
            tool: "USDConversionToolchain",
            output: "\(encoding.diagnosticName) conversion result has an invalid signature."
        )
    }

    private var requiredPrefix: [UInt8] {
        switch encoding {
        case .usd, .usda:
            []
        case .usdc:
            Array("PXR-USDC".utf8)
        case .usdz:
            [0x50, 0x4b]
        }
    }
}

private extension USDEncoding {
    var diagnosticName: String {
        switch self {
        case .usd:
            "USD"
        case .usda:
            "USDA"
        case .usdc:
            "USDC"
        case .usdz:
            "USDZ"
        }
    }
}
