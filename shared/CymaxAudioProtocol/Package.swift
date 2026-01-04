// swift-tools-version: 5.9
// CymaxAudioProtocol - Shared protocol definitions for Cymax Phone Audio

import PackageDescription

let package = Package(
    name: "CymaxAudioProtocol",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CymaxAudioProtocol",
            targets: ["CymaxAudioProtocol"]
        ),
    ],
    targets: [
        .target(
            name: "CymaxAudioProtocol",
            dependencies: [],
            path: "Sources/CymaxAudioProtocol"
        ),
    ]
)

