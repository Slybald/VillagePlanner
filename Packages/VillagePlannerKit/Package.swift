// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VillagePlannerKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "VillagePlannerKit", targets: ["VillagePlannerKit"]),
        .executable(name: "outils", targets: ["outils"]),
    ],
    targets: [
        .target(name: "VillagePlannerKit", resources: [.copy("Reference/Ressources/reference.json"), .copy("Reference/Ressources/conseils.json"), .copy("Reference/Ressources/noms-fr.json")]),
        .executableTarget(name: "outils", dependencies: ["VillagePlannerKit"]),
        .testTarget(
            name: "VillagePlannerKitTests",
            dependencies: ["VillagePlannerKit", "outils"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
