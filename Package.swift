// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VOX",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VOX", targets: ["VOX"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "VOX",
            path: "Sources/VOX",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "VOXTests",
            dependencies: ["VOX"],
            path: "Tests/VOXTests"
        )
    ]
)
