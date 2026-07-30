// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MediaShelf",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MediaShelfCore", targets: ["MediaShelfCore"]),
        .executable(name: "MediaShelf", targets: ["MediaShelfApp"])
    ],
    targets: [
        .target(
            name: "MediaShelfCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "MediaShelfApp",
            dependencies: ["MediaShelfCore"]
        ),
        .testTarget(
            name: "MediaShelfCoreTests",
            dependencies: ["MediaShelfCore"]
        )
    ]
)
