// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Glimmer",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "Glimmer",
            targets: ["Glimmer"]),
    ],
    dependencies: [],
    targets: [
        // Vendored from swiftlang/swift-cmark (gfm branch). See Sources/cmark-gfm/VENDORED.md.
        .target(
            name: "cmark-gfm",
            path: "Sources/cmark-gfm",
            exclude: ["scanners.re", "libcmark-gfm.pc.in", "config.h.in", "CMakeLists.txt", "COPYING", "VENDORED.md"]
        ),
        .target(
            name: "cmark-gfm-extensions",
            dependencies: ["cmark-gfm"],
            path: "Sources/cmark-gfm-extensions",
            exclude: ["CMakeLists.txt", "ext_scanners.re", "COPYING"]
        ),
        .target(
            name: "Glimmer",
            dependencies: ["cmark-gfm", "cmark-gfm-extensions"],
            resources: [.process("Engine/Resources")]
        ),
        .testTarget(
            name: "GlimmerTests",
            dependencies: ["Glimmer", "cmark-gfm", "cmark-gfm-extensions"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
