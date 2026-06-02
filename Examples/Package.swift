// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GlimmerDemo",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "GlimmerDemo", targets: ["GlimmerDemo"])
    ],
    dependencies: [
        // Reference the parent Glimmer package
        .package(name: "Glimmer", path: "..")
    ],
    targets: [
        .target(
            name: "GlimmerDemo",
            dependencies: [
                .product(name: "Glimmer", package: "Glimmer")
            ],
            path: "GlimmerDemo",
            exclude: ["Assets.xcassets", "GlimmerDemo.xcodeproj"]
        )
    ]
)
