// swift-tools-version: 6.2

import PackageDescription

// BackdropCore is the show model: everything that can be worked out without
// a window. No AppKit, so it can be tested against recorded outputs on its
// own.
//
// BackdropStage is the renderers: Core Text and Core Animation layer trees
// that paint cues into surfaces. It knows nothing about windows, so it can be
// tested headlessly too.
let package = Package(
    name: "BackdropCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "BackdropCore", targets: ["BackdropCore"]),
        .library(name: "BackdropStage", targets: ["BackdropStage"]),
    ],
    targets: [
        .target(name: "BackdropCore"),
        .target(name: "BackdropStage", dependencies: ["BackdropCore"]),
        .testTarget(
            name: "BackdropCoreTests",
            dependencies: ["BackdropCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "BackdropStageTests", dependencies: ["BackdropStage"]),
    ]
)
