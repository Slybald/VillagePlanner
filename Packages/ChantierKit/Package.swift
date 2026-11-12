// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChantierKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "ChantierKit", targets: ["ChantierKit"]),
        .executable(name: "outils", targets: ["outils"]),
    ],
    targets: [
        .target(name: "ChantierKit"),
        .executableTarget(name: "outils", dependencies: ["ChantierKit"]),
        .testTarget(
            name: "ChantierKitTests",
            dependencies: ["ChantierKit", "outils"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
