// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MediaShelf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MediaShelfCore", targets: ["MediaShelfCore"]),
        .executable(name: "MediaShelf", targets: ["MediaShelfApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/kingslay/FFmpegKit.git", exact: "6.1.4")
    ],
    targets: [
        .target(
            name: "DisplayCriteria",
            path: "Vendor/KSPlayer/DisplayCriteria",
            publicHeadersPath: "include"
        ),
        .target(
            name: "KSPlayer",
            dependencies: [
                .product(name: "FFmpegKit", package: "FFmpegKit"),
                "DisplayCriteria"
            ],
            path: "Vendor/KSPlayer/KSPlayer",
            exclude: ["Metal/Shaders.metal"]
        ),
        .target(
            name: "MediaShelfCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "MediaShelfApp",
            dependencies: [
                "MediaShelfCore",
                "KSPlayer"
            ]
        ),
        .testTarget(
            name: "MediaShelfCoreTests",
            dependencies: ["MediaShelfCore"]
        )
    ]
)
