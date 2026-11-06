// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nod",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nod", targets: ["Nod"]),
    ],
    targets: [
        // Pure logic: no AppKit, no UI. Everything testable without AirPods lives here.
        .target(
            name: "NodCore",
            path: "Sources/NodCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .executableTarget(
            name: "Nod",
            dependencies: ["NodCore"],
            path: "Sources/Nod",
            // Bundle inputs only; scripts/bundle.sh copies them into Nod.app.
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("CoreMotion"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        // Run through scripts/test.sh: Command Line Tools need extra Swift Testing flags.
        .testTarget(
            name: "NodCoreTests",
            dependencies: ["NodCore"],
            path: "Tests/NodCoreTests",
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
