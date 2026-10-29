// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "manicule",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ManiculeCore"),
        .executableTarget(name: "manicule", dependencies: ["ManiculeCore"]),
        .testTarget(name: "ManiculeCoreTests", dependencies: ["ManiculeCore"]),
        .testTarget(name: "maniculeTests", dependencies: ["manicule", "ManiculeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
