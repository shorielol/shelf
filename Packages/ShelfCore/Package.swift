// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShelfCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShelfCore", targets: ["ShelfCore"]),
    ],
    targets: [
        .target(
            name: "ShelfCore",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "ShelfCoreTests",
            dependencies: ["ShelfCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
