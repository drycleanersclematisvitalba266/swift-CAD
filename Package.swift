// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "SwiftCAD",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftCAD",
            targets: ["SwiftCAD"]
        ),
        .library(
            name: "CADIR",
            targets: ["CADIR"]
        ),
        .library(
            name: "CADKernel",
            targets: ["CADKernel"]
        ),
        .library(
            name: "CADExchange",
            targets: ["CADExchange"]
        ),
    ],
    targets: [
        .target(
            name: "CADCore"
        ),
        .target(
            name: "CADIR",
            dependencies: ["CADCore"]
        ),
        .target(
            name: "CADKernel",
            dependencies: ["CADCore", "CADIR"]
        ),
        .target(
            name: "CADExchange",
            dependencies: ["CADCore", "CADIR", "CADKernel"]
        ),
        .target(
            name: "SwiftCAD",
            dependencies: ["CADCore", "CADIR", "CADKernel", "CADExchange"]
        ),
        .testTarget(
            name: "CADCoreTests",
            dependencies: ["CADCore"]
        ),
        .testTarget(
            name: "CADIRTests",
            dependencies: ["CADCore", "CADIR"]
        ),
        .testTarget(
            name: "CADKernelTests",
            dependencies: ["CADCore", "CADIR", "CADKernel"]
        ),
        .testTarget(
            name: "CADExchangeTests",
            dependencies: ["CADCore", "CADIR", "CADKernel", "CADExchange"]
        ),
        .testTarget(
            name: "SwiftCADTests",
            dependencies: ["SwiftCAD", "CADExchange", "CADKernel", "CADIR", "CADCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
