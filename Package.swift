// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "locus",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "locus", targets: ["LocusCLI"]),
        .library(name: "LocusCore", targets: ["LocusCore"]),
    ],
    dependencies: [
        // Pinned to the 600.x line: builds cleanly in Swift 5 language mode even on
        // very new toolchains (6.x). The 509.x line is the documented fallback.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        .target(
            name: "LocusCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/LocusCore"
        ),
        .executableTarget(
            name: "LocusCLI",
            dependencies: ["LocusCore"],
            path: "Sources/LocusCLI"
        ),
        .testTarget(
            name: "LocusCoreTests",
            dependencies: ["LocusCore"],
            path: "Tests/LocusCoreTests"
        ),
    ]
)
