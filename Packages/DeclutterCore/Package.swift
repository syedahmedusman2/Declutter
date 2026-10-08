// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DeclutterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DeclutterCore",
            targets: ["DeclutterCore"]
        )
    ],
    targets: [
        .target(
            name: "DeclutterCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DeclutterCoreTests",
            dependencies: ["DeclutterCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)

