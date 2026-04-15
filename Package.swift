// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSift",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MacSift", targets: ["MacSift"])
    ],
    targets: [
        .executableTarget(
            name: "MacSift",
            path: "MacSift",
            // SwiftPM picks up .lproj folders automatically when
            // `defaultLocalization` is set on the Package. We still list
            // them here explicitly so the build fails loudly if the
            // resource layout drifts.
            resources: [
                .process("Resources/en.lproj/Localizable.strings"),
                .process("Resources/fr.lproj/Localizable.strings"),
            ]
        ),
        .testTarget(
            name: "MacSiftTests",
            dependencies: ["MacSift"],
            path: "MacSiftTests"
        )
    ]
)
