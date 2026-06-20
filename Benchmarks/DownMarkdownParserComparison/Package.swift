// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownMarkdownParserComparison",
    platforms: [
        .iOS(.v18)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/johnxnguyen/Down.git", exact: "0.9.5"),
    ],
    targets: [
        .testTarget(
            name: "DownMarkdownParserComparisonTests",
            dependencies: [
                .product(name: "Glimmer", package: "Glimmer"),
                .product(name: "Down", package: "Down"),
            ]
        ),
    ]
)
