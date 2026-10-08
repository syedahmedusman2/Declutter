// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DownloadOrganizerCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "DownloadOrganizerCore",
            targets: ["DownloadOrganizerCore"]
        )
    ],
    targets: [
        .target(
            name: "DownloadOrganizerCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DownloadOrganizerCoreTests",
            dependencies: ["DownloadOrganizerCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
