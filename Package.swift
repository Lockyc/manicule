// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "manicule",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "ManiculeCore"),
        .executableTarget(name: "manicule", dependencies: ["ManiculeCore", .product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "ManiculeCoreTests", dependencies: ["ManiculeCore"]),
        .testTarget(name: "maniculeTests", dependencies: ["manicule", "ManiculeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
