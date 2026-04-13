// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSift",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MacSift", targets: ["MacSift"])
    ],
    targets: [
        .executableTarget(
            name: "MacSift",
            path: "MacSift"
        ),
        .testTarget(
            name: "MacSiftTests",
            dependencies: ["MacSift"],
            path: "MacSiftTests"
        )
    ]
)
