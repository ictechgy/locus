// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "breadcrumb",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "breadcrumb", targets: ["BreadcrumbCLI"]),
        .library(name: "BreadcrumbCore", targets: ["BreadcrumbCore"]),
    ],
    dependencies: [
        // Pinned to the 600.x line: builds cleanly in Swift 5 language mode even on
        // very new toolchains (6.x). The 509.x line is the documented fallback.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.1"),
    ],
    targets: [
        .target(
            name: "BreadcrumbCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/BreadcrumbCore"
        ),
        .executableTarget(
            name: "BreadcrumbCLI",
            dependencies: ["BreadcrumbCore"],
            path: "Sources/BreadcrumbCLI"
        ),
        .testTarget(
            name: "BreadcrumbCoreTests",
            dependencies: ["BreadcrumbCore"],
            path: "Tests/BreadcrumbCoreTests"
        ),
    ]
)
