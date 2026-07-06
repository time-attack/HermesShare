// swift-tools-version:6.2
import PackageDescription

// The Shared package is the single source of truth for the HermesShare data model
// and renderer. It is linked *statically* into both the host app and the iMessage
// extension, so there is no framework to embed and no runtime dylib lookup to get
// wrong from inside the app-extension sandbox.
let package = Package(
    name: "HermesShared",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "HermesShared",
            type: .static,
            targets: ["HermesShared"]
        )
    ],
    targets: [
        .target(
            name: "HermesShared",
            exclude: ["HERMES_LAYOUT_GUIDE.md"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HermesSharedTests",
            dependencies: ["HermesShared"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
