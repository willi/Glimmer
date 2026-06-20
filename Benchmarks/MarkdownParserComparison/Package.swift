// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkdownParserComparison",
    platforms: [
        .iOS(.v18)
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0"),
        .package(url: "https://github.com/JohnSundell/Ink.git", exact: "0.6.0"),
        .package(url: "https://github.com/bmoliveira/MarkdownKit.git", exact: "1.7.3"),
        .package(url: "https://github.com/SimonFairbairn/SwiftyMarkdown.git", exact: "1.2.4"),
    ],
    targets: [
        .testTarget(
            name: "MarkdownParserComparisonTests",
            dependencies: [
                .product(name: "Glimmer", package: "Glimmer"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Ink", package: "Ink"),
                .product(name: "MarkdownKit", package: "MarkdownKit"),
                .product(name: "SwiftyMarkdown", package: "SwiftyMarkdown"),
            ]
        ),
    ]
)
