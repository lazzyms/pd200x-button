// swift-tools-version: 5.9

import PackageDescription

var packageTargets: [Target] = [
    .target(name: "PD200XTarget"),
    .executableTarget(
        name: "PD200XButtonProbe",
        dependencies: ["PD200XTarget"]
    ),
    .executableTarget(
        name: "PD200XButtonMenu",
        dependencies: ["PD200XTarget"]
    ),
]

packageTargets.append(
    .testTarget(
        name: "PD200XButtonProbeTests",
        dependencies: ["PD200XButtonProbe", "PD200XTarget"]
    )
)

let package = Package(
    name: "PD200XButton",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "pd200x-button-probe", targets: ["PD200XButtonProbe"]),
        .executable(name: "PD200XButtonMenu", targets: ["PD200XButtonMenu"]),
    ],
    targets: packageTargets,
    swiftLanguageVersions: [.v5]
)
